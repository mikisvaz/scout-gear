require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestMiscDigest < Test::Unit::TestCase
  def test_digest_str
    o = {:a => [1,2,3], :b => [1.1, 0.00001, 'hola']}
    assert Misc.digest_str(o).include? "hola"
  end
end

