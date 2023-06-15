require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestScout < Test::Unit::TestCase
  def test_version
    assert_equal 3, Scout.version.split(".").length
  end
end

