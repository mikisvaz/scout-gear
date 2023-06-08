require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestSSH < Test::Unit::TestCase
  def test_marshal
    return unless SSHLine.reach?

    assert TrueClass === SSHLine.rbbt(:default, 'true')
  end

  def test_localhost
    SSHLine.rbbt('localhost', 'true')
  end
end

