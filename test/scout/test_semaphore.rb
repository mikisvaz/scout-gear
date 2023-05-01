require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/work_queue/worker'
class TestSemaphore < Test::Unit::TestCase

  def test_simple
    ScoutSemaphore.with_semaphore 1 do |sem|
      10.times do
        ScoutSemaphore.synchronize(sem) do
          assert true
        end
      end
    end
  end
end

