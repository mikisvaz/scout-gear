require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestNamedArrayEntity < Test::Unit::TestCase
  def setup
    m = Module.new do
      extend Entity
      self.format = "SomeEntity"

      property :prop do
        "PROP: #{self}"
      end
    end
  end

  def test_true
    a = NamedArray.setup(["a", "b"], %w(SomeEntity Other))
    assert a["SomeEntity"].respond_to?(:prop)
  end
end

