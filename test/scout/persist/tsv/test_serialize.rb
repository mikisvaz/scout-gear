require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestClass < Test::Unit::TestCase
  def test_serializer_module
    m = TSVAdapter.serializer_module :marshal
    v = [1, :a]
    d = m.dump(v)
    assert_equal v, m.load(d) 
  end
end

