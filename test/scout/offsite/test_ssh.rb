require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestSSH < Test::Unit::TestCase
  def server
    @@server ||= begin
                   ENV["SCOUT_OFFSITE"] || 'localhost'
                 end
  end

  def test_marshal
    sss 0
    return unless SSHLine.reach?(server)
    return unless SSHLine.reach?(server)
    return unless SSHLine.reach?(server)
    return unless SSHLine.reach?(server)

    assert TrueClass === SSHLine.rbbt(server, 'true')
  end
end

