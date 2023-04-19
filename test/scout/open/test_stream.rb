require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/path'
require 'scout/open'

class TestOpenStream < Test::Unit::TestCase
  def test_consume_stream
    content =<<-EOF
1
2
3
4
    EOF
    TmpFile.with_file(content) do |file|
      TmpFile.with_file do |target|
        f = File.open(file)
        Open.consume_stream(f, false, target)
        assert_equal content, File.open(target).read
      end
    end
  end

  def test_sensible_write
    content =<<-EOF
1
2
3
4
    EOF
    TmpFile.with_file(content) do |file|
      TmpFile.with_file do |target|
        f = File.open(file)
        Open.sensible_write(target, f)
        assert_equal content, File.open(target).read
      end
    end
  end

end

