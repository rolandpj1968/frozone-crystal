require "spec"
require "../src/ruby_hash"
require "../src/ruby_array"
require "../src/ruby_integer"
require "../src/ruby_string/ruby_string"
require "../src/ruby_nil"
require "../src/ruby_bool"

# Helpers
private def ri(n : Int64) : RubyInteger
  RubyInteger.new(n)
end

private def rs(s : String) : RubyString
  RubyString.new(s, RubyEncoding::UTF_8)
end

describe RubyHash do
  describe "#initialize" do
    it "creates an empty hash" do
      h = RubyHash.new
      h.size.should eq ri(0)
      h.empty?.should eq RubyBool::TRUE
    end

    it "accepts a default value" do
      h = RubyHash.new(ri(0))
      h.default.should eq ri(0)
    end
  end

  describe "#[]= and #[]" do
    it "stores and retrieves values" do
      h = RubyHash.new
      h[ri(1)] = ri(100)
      h[ri(2)] = ri(200)
      h[ri(1)].should eq ri(100)
      h[ri(2)].should eq ri(200)
    end

    it "returns default for missing keys" do
      h = RubyHash.new
      h[ri(99)].should eq RubyNil::INSTANCE
    end

    it "returns configured default for missing keys" do
      h = RubyHash.new(ri(42))
      h[ri(99)].should eq ri(42)
    end

    it "overwrites existing values" do
      h = RubyHash.new
      h[ri(1)] = ri(10)
      h[ri(1)] = ri(20)
      h[ri(1)].should eq ri(20)
      h.size.should eq ri(1)
    end

    it "supports string keys" do
      h = RubyHash.new
      h[rs("foo")] = ri(1)
      h[rs("foo")].should eq ri(1)
    end

    it "supports nil as a key" do
      h = RubyHash.new
      h[RubyNil::INSTANCE] = ri(42)
      h[RubyNil::INSTANCE].should eq ri(42)
    end
  end

  describe "#[]?" do
    it "returns the value when present" do
      h = RubyHash.new
      h[ri(1)] = ri(10)
      h[ri(1)]?.should eq ri(10)
    end

    it "returns nil (Crystal nil) for missing keys" do
      h = RubyHash.new
      h[ri(99)]?.should be_nil
    end
  end

  describe "#delete" do
    it "removes a key and returns it (Ruby semantics)" do
      h = RubyHash.new
      h[ri(1)] = ri(10)
      h.delete(ri(1))
      h[ri(1)].should eq RubyNil::INSTANCE
      h.size.should eq ri(0)
    end

    it "returns RubyNil when key is absent" do
      h = RubyHash.new
      h.delete(ri(99)).should eq RubyNil::INSTANCE
    end
  end

  describe "#key?" do
    it "returns TRUE when key exists" do
      h = RubyHash.new
      h[ri(1)] = ri(10)
      h.key?(ri(1)).should eq RubyBool::TRUE
    end

    it "returns FALSE when key is absent" do
      RubyHash.new.key?(ri(1)).should eq RubyBool::FALSE
    end
  end

  describe "#value?" do
    it "returns TRUE when value exists" do
      h = RubyHash.new
      h[ri(1)] = ri(42)
      h.value?(ri(42)).should eq RubyBool::TRUE
    end

    it "returns FALSE when value is absent" do
      RubyHash.new.value?(ri(99)).should eq RubyBool::FALSE
    end
  end

  describe "#size / #length" do
    it "tracks size correctly" do
      h = RubyHash.new
      h.size.should eq ri(0)
      h[ri(1)] = ri(1)
      h.size.should eq ri(1)
      h[ri(2)] = ri(2)
      h.size.should eq ri(2)
      h.delete(ri(1))
      h.size.should eq ri(1)
      h.length.should eq ri(1)
    end
  end

  describe "#clear" do
    it "removes all entries" do
      h = RubyHash.new
      h[ri(1)] = ri(1)
      h[ri(2)] = ri(2)
      h.clear
      h.size.should eq ri(0)
      h.empty?.should eq RubyBool::TRUE
    end
  end

  describe "#merge / #merge!" do
    it "merge returns a new hash with entries from both" do
      a = RubyHash.new
      a[ri(1)] = ri(10)
      b = RubyHash.new
      b[ri(2)] = ri(20)
      c = a.merge(b)
      c[ri(1)].should eq ri(10)
      c[ri(2)].should eq ri(20)
      a.size.should eq ri(1) # unchanged
    end

    it "merge! updates in place and later values win" do
      a = RubyHash.new
      a[ri(1)] = ri(10)
      a[ri(2)] = ri(20)
      b = RubyHash.new
      b[ri(2)] = ri(99)
      b[ri(3)] = ri(30)
      a.merge!(b)
      a[ri(1)].should eq ri(10)
      a[ri(2)].should eq ri(99)
      a[ri(3)].should eq ri(30)
      a.size.should eq ri(3)
    end
  end

  describe "#keys / #values / #to_a" do
    it "returns keys in insertion order" do
      h = RubyHash.new
      h[ri(3)] = ri(30)
      h[ri(1)] = ri(10)
      h[ri(2)] = ri(20)
      keys = h.keys
      keys[0_i64].should eq ri(3)
      keys[1_i64].should eq ri(1)
      keys[2_i64].should eq ri(2)
    end

    it "returns values in insertion order" do
      h = RubyHash.new
      h[ri(1)] = ri(10)
      h[ri(2)] = ri(20)
      vals = h.values
      vals[0_i64].should eq ri(10)
      vals[1_i64].should eq ri(20)
    end

    it "to_a returns array of [k, v] pairs" do
      h = RubyHash.new
      h[ri(1)] = ri(10)
      pairs = h.to_a
      pairs.length.should eq ri(1)
      pair = pairs[0_i64].as(RubyArray)
      pair[0_i64].should eq ri(1)
      pair[1_i64].should eq ri(10)
    end
  end

  describe "#each" do
    it "iterates key-value pairs" do
      h = RubyHash.new
      h[ri(1)] = ri(10)
      h[ri(2)] = ri(20)
      count = 0
      h.each { |_, _| count += 1 }
      count.should eq 2
    end
  end

  describe "#map_values / #map_values!" do
    it "map_values returns a new hash with transformed values" do
      h = RubyHash.new
      h[ri(1)] = ri(10)
      h[ri(2)] = ri(20)
      h2 = h.map_values { |v| ri(v.as(RubyInteger).to_i64 * 2) }
      h2[ri(1)].should eq ri(20)
      h2[ri(2)].should eq ri(40)
      h[ri(1)].should eq ri(10) # original unchanged
    end

    it "map_values! updates values in place" do
      h = RubyHash.new
      h[ri(1)] = ri(10)
      h.map_values! { |v| ri(v.as(RubyInteger).to_i64 + 1) }
      h[ri(1)].should eq ri(11)
    end
  end

  describe "#compare_by_identity!" do
    it "uses object identity for key comparison" do
      h = RubyHash.new
      h.compare_by_identity!
      h.compare_by_identity?.should eq RubyBool::TRUE
      k1 = ri(1)
      k2 = ri(1) # different object, same value
      h[k1] = ri(10)
      # k2 has same value but different identity — should not match
      h[k2].should eq RubyNil::INSTANCE
      h[k1].should eq ri(10)
    end
  end

  describe "#==" do
    it "returns true for equal hashes" do
      a = RubyHash.new
      a[ri(1)] = ri(10)
      b = RubyHash.new
      b[ri(1)] = ri(10)
      (a == b).should be_true
    end

    it "returns false when values differ" do
      a = RubyHash.new
      a[ri(1)] = ri(10)
      b = RubyHash.new
      b[ri(1)] = ri(99)
      (a == b).should be_false
    end

    it "returns false when sizes differ" do
      a = RubyHash.new
      a[ri(1)] = ri(10)
      b = RubyHash.new
      (a == b).should be_false
    end

    it "returns false when compared to non-hash RubyObject" do
      h = RubyHash.new
      (h == RubyNil::INSTANCE).should be_false
    end
  end

  describe "#hash" do
    it "returns equal hashes for equal maps" do
      a = RubyHash.new
      a[ri(1)] = ri(10)
      b = RubyHash.new
      b[ri(1)] = ri(10)
      a.hash.should eq b.hash
    end
  end

  describe "#inspect / #to_s" do
    it "formats as Ruby hash literal" do
      h = RubyHash.new
      h[ri(1)] = ri(10)
      h.inspect.should eq "{1=>10}"
      h.to_s.should eq "{1=>10}"
    end

    it "formats empty hash" do
      RubyHash.new.inspect.should eq "{}"
    end
  end

  describe "RubyObject base" do
    it "inherits from RubyObject" do
      RubyHash.new.should be_a(RubyObject)
    end

    it "truthy? is true" do
      RubyHash.new.truthy?.should be_true
    end

    it "ruby_nil? is false" do
      RubyHash.new.ruby_nil?.should be_false
    end

    it "not returns RubyBool::FALSE" do
      RubyHash.new.not.should eq RubyBool::FALSE
    end
  end
end
