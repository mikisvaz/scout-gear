require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestSocket < Test::Unit::TestCase

  class DoneProcessing end

  def test_simple
    socket = WorkQueue::Socket.new

    socket.write 1
    socket.write 2
    socket.write "STRING"
    socket.write :string

    assert_equal 1, socket.read
    assert_equal 2, socket.read
    assert_equal "STRING", socket.read
    assert_equal :string, socket.read

    socket.close_write
    assert_raise ClosedStream do
      socket.read
    end
  end

  def __test_speed
    socket = WorkQueue::Socket.new

    num = 50_000

    Thread.new do
      num.times do |i|
        socket.write nil
      end
      socket.write DoneProcessing.new
    end

    bar = Log::ProgressBar.new num
    while true
      i = socket.read
      bar.tick
      break if DoneProcessing === i
    end
    bar.done
  end
end

