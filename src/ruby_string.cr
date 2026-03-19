# RubyString — Crystal implementation of Ruby string semantics.
#
# Design decision: CLASS not struct.
#
# Ruby strings are mutable reference objects. Crystal structs are value types:
# every assignment copies the value, and mutating methods require the receiver
# to be a mutable variable. That mismatch makes structs awkward here because
# two variables pointing at "the same" string would not share mutations —
# exactly the opposite of Ruby semantics. Using a class gives us reference
# semantics: `a = b` makes both names point to the same object, and
# `a.concat_bytes!(x)` is visible through `b`, matching Ruby behaviour.

# ---------------------------------------------------------------------------
# Encoding enum
# ---------------------------------------------------------------------------

enum RubyEncoding
  UTF_8
  ASCII_8BIT  # also known as BINARY
  US_ASCII
  UTF_16LE
  UTF_16BE
  UTF_32LE
  UTF_32BE
  ISO_8859_1
  WINDOWS_1252
  ISO_8859_2
  ISO_8859_15
  EUC_JP
  Shift_JIS
  UTF_8_MAC   # NFD-normalised UTF-8, used on macOS HFS+

  # Alias so callers can write RubyEncoding::BINARY
  def self.binary : RubyEncoding
    ASCII_8BIT
  end
end

# ---------------------------------------------------------------------------
# Exception raised when mutating a frozen RubyString
# ---------------------------------------------------------------------------

class RubyFrozenError < Exception
  def initialize(msg : String = "can't modify frozen String: \"...\"")
    super(msg)
  end
end

# ---------------------------------------------------------------------------
# RubyString
# ---------------------------------------------------------------------------

class RubyString
  # ------------------------------------------------------------------
  # Flag bit positions in @flags : UInt8
  # ------------------------------------------------------------------
  FROZEN_BIT              = 0u8
  CHILLED_BIT             = 1u8
  ASCII_ONLY_VALID_BIT    = 2u8   # cached result is populated
  ASCII_ONLY_BIT          = 3u8   # cached value
  VALID_ENC_VALID_BIT     = 4u8   # cached result is populated
  VALID_ENC_BIT           = 5u8   # cached value

  # Mask covering all cache bits (bits 2-5); cleared on any mutation.
  CACHE_MASK = (1u8 << ASCII_ONLY_VALID_BIT) |
               (1u8 << ASCII_ONLY_BIT)        |
               (1u8 << VALID_ENC_VALID_BIT)   |
               (1u8 << VALID_ENC_BIT)

  # ------------------------------------------------------------------
  # Storage
  # ------------------------------------------------------------------

  @bytes    : Bytes
  @encoding : RubyEncoding
  @flags    : UInt8

  # ------------------------------------------------------------------
  # Constructors
  # ------------------------------------------------------------------

  # Primary initializer: take a Bytes slice, an encoding, and optional flags.
  # The slice is *copied* so the caller's buffer cannot alias our storage.
  # flags defaults to 0 (no frozen, no chilled, no cached values).
  # The internal `flags` param lets `dup` pass 0 explicitly; it is not part
  # of the public API described in the spec (the public factory is `.new`).
  def initialize(bytes : Bytes, encoding : RubyEncoding, flags : UInt8 = 0u8)
    @bytes    = bytes.dup
    @encoding = encoding
    @flags    = flags & ~CACHE_MASK  # never inherit stale cache from caller
  end

  # Construct from a Crystal String.  The string is always stored as its
  # UTF-8 bytes unless a different encoding tag is requested (no transcoding).
  def self.from_string(s : String, encoding : RubyEncoding = RubyEncoding::UTF_8) : RubyString
    new(s.to_slice, encoding)
  end

  # Empty string with the given encoding.
  def self.empty(encoding : RubyEncoding = RubyEncoding::UTF_8) : RubyString
    new(Bytes.empty, encoding)
  end

  # Single-byte string.  Defaults to ASCII_8BIT because a lone byte has no
  # meaningful higher encoding context.
  def self.from_byte(b : UInt8, encoding : RubyEncoding = RubyEncoding::ASCII_8BIT) : RubyString
    new(Bytes[b], encoding)
  end

  # ------------------------------------------------------------------
  # Flag helpers (private)
  # ------------------------------------------------------------------

  private def flag?(bit : UInt8) : Bool
    (@flags & (1u8 << bit)) != 0u8
  end

  private def set_flag!(bit : UInt8) : Nil
    @flags |= (1u8 << bit)
  end

  private def clear_flag!(bit : UInt8) : Nil
    @flags &= ~(1u8 << bit)
  end

  private def clear_caches! : Nil
    @flags &= ~CACHE_MASK
  end

  private def check_frozen! : Nil
    raise RubyFrozenError.new if frozen?
  end

  # ------------------------------------------------------------------
  # Basic properties
  # ------------------------------------------------------------------

  def bytesize : Int32
    @bytes.size
  end

  def empty? : Bool
    @bytes.size == 0
  end

  def encoding : RubyEncoding
    @encoding
  end

  def frozen? : Bool
    flag?(FROZEN_BIT)
  end

  def chilled? : Bool
    flag?(CHILLED_BIT)
  end

  # ------------------------------------------------------------------
  # Byte access
  # ------------------------------------------------------------------

  # Returns the byte value at index i, or -1 if out of range.
  # Supports negative indices (Ruby semantics: -1 = last byte).
  # The VM layer is responsible for converting -1 back to nil when needed.
  def get_byte(i : Int32) : Int32
    idx = i < 0 ? @bytes.size + i : i
    return -1 if idx < 0 || idx >= @bytes.size
    @bytes[idx].to_i32
  end

  # Set a byte at index i.  Clears encoding caches.
  # Raises RubyFrozenError if frozen.
  # Returns the byte value written.
  def set_byte!(i : Int32, b : UInt8) : UInt8
    check_frozen!
    idx = i < 0 ? @bytes.size + i : i
    raise IndexError.new("index #{i} out of string") if idx < 0 || idx >= @bytes.size
    @bytes[idx] = b
    clear_caches!
    b
  end

  # ------------------------------------------------------------------
  # Mutation
  # ------------------------------------------------------------------

  # Append the bytes of *other* to self in-place.
  # Raises RubyFrozenError if frozen.
  # Returns self.
  def concat_bytes!(other : RubyString) : RubyString
    check_frozen!
    new_bytes = Bytes.new(@bytes.size + other.@bytes.size)
    @bytes.copy_to(new_bytes)
    other.@bytes.copy_to(new_bytes + @bytes.size)
    @bytes = new_bytes
    clear_caches!
    self
  end

  # Change encoding tag without touching the bytes.
  # Raises RubyFrozenError if frozen.
  # Returns self.
  def force_encoding!(enc : RubyEncoding) : RubyString
    check_frozen!
    @encoding = enc
    clear_caches!
    self
  end

  # Replace content in-place (bytes and encoding) from *other*.
  # Raises RubyFrozenError if frozen.
  # Returns self.
  def replace!(other : RubyString) : RubyString
    check_frozen!
    @bytes    = other.@bytes.dup
    @encoding = other.@encoding
    clear_caches!
    self
  end

  # ------------------------------------------------------------------
  # Encoding queries — lazy cached
  # ------------------------------------------------------------------

  # Returns true if all characters in the string are ASCII (codepoints < 128).
  #
  # For ASCII_8BIT / US_ASCII: scan for any byte > 127.
  # For UTF_8: additionally verify the bytes form valid UTF-8 (a string with
  # invalid UTF-8 sequences is not "ascii only" even if the bytes happen to be
  # all < 128, because it is not a valid string).
  # For other encodings: scan bytes (best-effort; full table validation deferred).
  def ascii_only? : Bool
    if flag?(ASCII_ONLY_VALID_BIT)
      return flag?(ASCII_ONLY_BIT)
    end

    result = compute_ascii_only
    set_flag!(ASCII_ONLY_VALID_BIT)
    if result
      set_flag!(ASCII_ONLY_BIT)
    else
      clear_flag!(ASCII_ONLY_BIT)
    end
    result
  end

  # Returns true if the bytes form a valid sequence for the declared encoding.
  #
  # ASCII_8BIT: always true (it is a raw byte container).
  # US_ASCII:   all bytes <= 127.
  # UTF_8:      valid UTF-8 sequences.
  # Others:     stubbed true (full validation needs conversion tables).
  def valid_encoding? : Bool
    if flag?(VALID_ENC_VALID_BIT)
      return flag?(VALID_ENC_BIT)
    end

    result = compute_valid_encoding
    set_flag!(VALID_ENC_VALID_BIT)
    if result
      set_flag!(VALID_ENC_BIT)
    else
      clear_flag!(VALID_ENC_BIT)
    end
    result
  end

  # ------------------------------------------------------------------
  # Freezing / duplication
  # ------------------------------------------------------------------

  # Mark this string as frozen.  Returns self.
  def freeze! : RubyString
    set_flag!(FROZEN_BIT)
    self
  end

  # Return a new, unfrozen, unchilled copy of this string.
  def dup : RubyString
    # Pass 0u8 as flags — the constructor strips caches anyway,
    # and we explicitly want frozen/chilled cleared.
    RubyString.new(@bytes, @encoding, 0u8)
  end

  # ------------------------------------------------------------------
  # Conversion
  # ------------------------------------------------------------------

  # Best-effort conversion to a Crystal String (UTF-8).
  # Invalid bytes are replaced with the UTF-8 replacement character U+FFFD.
  def to_crystal_string : String
    case @encoding
    when RubyEncoding::UTF_8, RubyEncoding::US_ASCII
      # Crystal's String.new replaces invalid UTF-8 with replacement chars
      # when given invalid bytes via the overload that takes Bytes + "invalid"
      # handling.  We use the scrub approach via a String::Builder.
      scrub_utf8(@bytes)
    when RubyEncoding::ASCII_8BIT
      # Treat each byte as latin-1 / ISO-8859-1; non-ASCII become U+0080..U+00FF
      String.build do |io|
        @bytes.each do |b|
          if b < 0x80u8
            io.write_byte(b)
          else
            # Encode the codepoint (b as U+00xx) in UTF-8: two-byte sequence
            io.write_byte(0xC0u8 | (b >> 6))
            io.write_byte(0x80u8 | (b & 0x3Fu8))
          end
        end
      end
    else
      # For other encodings, do a best-effort UTF-8 scrub of the raw bytes.
      scrub_utf8(@bytes)
    end
  end

  # Return a copy of the underlying raw bytes.
  def raw_bytes : Bytes
    @bytes.dup
  end

  # ------------------------------------------------------------------
  # Comparison
  # ------------------------------------------------------------------

  # Ruby eql? semantics: same bytes AND same encoding.
  def ==(other : RubyString) : Bool
    @encoding == other.@encoding && @bytes == other.@bytes
  end

  # Spaceship on raw bytes (lexicographic byte order).
  def bytesize_compare(other : RubyString) : Int32
    min_size = Math.min(@bytes.size, other.@bytes.size)
    0.upto(min_size - 1) do |i|
      cmp = @bytes[i].to_i32 - other.@bytes[i].to_i32
      return cmp if cmp != 0
    end
    @bytes.size - other.@bytes.size
  end

  # ------------------------------------------------------------------
  # Private: encoding computation
  # ------------------------------------------------------------------

  private def compute_ascii_only : Bool
    case @encoding
    when RubyEncoding::ASCII_8BIT, RubyEncoding::US_ASCII
      all_bytes_ascii?
    when RubyEncoding::UTF_8
      # Must be valid UTF-8 AND all codepoints < 128 (which for valid UTF-8
      # means all bytes < 128).
      valid_utf8? && all_bytes_ascii?
    else
      # Best-effort: byte scan
      all_bytes_ascii?
    end
  end

  private def compute_valid_encoding : Bool
    case @encoding
    when RubyEncoding::ASCII_8BIT
      true
    when RubyEncoding::US_ASCII
      all_bytes_ascii?
    when RubyEncoding::UTF_8
      valid_utf8?
    else
      # Stub: full table-based validation deferred
      true
    end
  end

  private def all_bytes_ascii? : Bool
    @bytes.each do |b|
      return false if b > 127u8
    end
    true
  end

  # Simple UTF-8 validator using a state machine.
  #
  # UTF-8 byte patterns:
  #   0xxxxxxx                                     — 1-byte (U+0000..U+007F)
  #   110xxxxx 10xxxxxx                            — 2-byte (U+0080..U+07FF)
  #   1110xxxx 10xxxxxx 10xxxxxx                   — 3-byte (U+0800..U+FFFF)
  #   11110xxx 10xxxxxx 10xxxxxx 10xxxxxx          — 4-byte (U+10000..U+10FFFF)
  #
  # Rejects: overlong encodings, surrogate halves (U+D800..U+DFFF),
  # codepoints above U+10FFFF, and unexpected continuation bytes.
  private def valid_utf8? : Bool
    i = 0
    while i < @bytes.size
      b = @bytes[i]
      if b < 0x80u8
        # ASCII byte — single byte sequence
        i += 1
      elsif b < 0xC0u8
        # 0x80..0xBF: unexpected continuation byte
        return false
      elsif b < 0xE0u8
        # 2-byte sequence: 110xxxxx 10xxxxxx
        return false if i + 1 >= @bytes.size
        return false unless continuation?(@bytes[i + 1])
        # Reject overlong: 2-byte must encode >= 0x80
        return false if b < 0xC2u8
        i += 2
      elsif b < 0xF0u8
        # 3-byte sequence: 1110xxxx 10xxxxxx 10xxxxxx
        return false if i + 2 >= @bytes.size
        return false unless continuation?(@bytes[i + 1]) && continuation?(@bytes[i + 2])
        # Reject overlong: 3-byte must encode >= 0x0800
        if b == 0xE0u8
          return false if @bytes[i + 1] < 0xA0u8
        end
        # Reject surrogates: U+D800..U+DFFF (0xED A0 80 .. 0xED BF BF)
        if b == 0xEDu8
          return false if @bytes[i + 1] >= 0xA0u8
        end
        i += 3
      elsif b < 0xF8u8
        # 4-byte sequence: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
        return false if i + 3 >= @bytes.size
        return false unless continuation?(@bytes[i + 1]) &&
                            continuation?(@bytes[i + 2]) &&
                            continuation?(@bytes[i + 3])
        # Reject overlong: 4-byte must encode >= 0x10000
        if b == 0xF0u8
          return false if @bytes[i + 1] < 0x90u8
        end
        # Reject codepoints > U+10FFFF (0xF4 90 80 80 and above)
        if b == 0xF4u8
          return false if @bytes[i + 1] >= 0x90u8
        end
        return false if b > 0xF4u8
        i += 4
      else
        # 0xF8..0xFF: invalid
        return false
      end
    end
    true
  end

  private def continuation?(b : UInt8) : Bool
    b >= 0x80u8 && b < 0xC0u8
  end

  # Scrub invalid UTF-8 bytes, replacing them with U+FFFD (EF BF BD).
  private def scrub_utf8(bytes : Bytes) : String
    String.build do |io|
      i = 0
      while i < bytes.size
        b = bytes[i]
        seq_len = utf8_sequence_length(b)
        if seq_len == 0 || i + seq_len > bytes.size || !valid_utf8_sequence?(bytes, i, seq_len)
          io << "\u{FFFD}"
          i += 1
        else
          seq_len.times { |j| io.write_byte(bytes[i + j]) }
          i += seq_len
        end
      end
    end
  end

  private def utf8_sequence_length(b : UInt8) : Int32
    if b < 0x80u8;    1
    elsif b < 0xC2u8; 0  # continuation or overlong leader
    elsif b < 0xE0u8; 2
    elsif b < 0xF0u8; 3
    elsif b <= 0xF4u8; 4
    else;              0
    end
  end

  private def valid_utf8_sequence?(bytes : Bytes, start : Int32, len : Int32) : Bool
    b = bytes[start]
    case len
    when 1
      b < 0x80u8
    when 2
      continuation?(bytes[start + 1]) && b >= 0xC2u8
    when 3
      c1 = bytes[start + 1]
      continuation?(c1) && continuation?(bytes[start + 2]) &&
        !(b == 0xE0u8 && c1 < 0xA0u8) &&  # overlong
        !(b == 0xEDu8 && c1 >= 0xA0u8)     # surrogates
    when 4
      c1 = bytes[start + 1]
      continuation?(c1) && continuation?(bytes[start + 2]) && continuation?(bytes[start + 3]) &&
        !(b == 0xF0u8 && c1 < 0x90u8) &&   # overlong
        !(b == 0xF4u8 && c1 >= 0x90u8)     # > U+10FFFF
    else
      false
    end
  end
end
