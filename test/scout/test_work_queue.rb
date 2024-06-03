require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/log'
class TestWorkQueue < Test::Unit::TestCase
  def test_a_queue_remove_workers
    num = 10
    reps = 10_000
    q = WorkQueue.new num do |obj|
      [Process.pid, obj.inspect] * " "
    end

    output = []
    q.process do |out|
      output << out
    end

    reps.times do |i|
      q.write i
    end

    (num - 1).times do q.remove_one_worker end

    Thread.pass until q.workers.length == 1

    w = q.add_worker do |obj|
      "HEY"
    end

    reps.times do |i|
      q.write i + reps
    end

    q.close
    q.join

    assert_equal reps * 2, output.length
    assert output.include?("HEY")
  end

  def test_queue
    num = 10
    reps = 1_000
    q = WorkQueue.new num do |obj|
      [Process.pid.to_s, obj.to_s] * " "
    end

    res = []
    q.process do |out|
      res << out
    end

    pid = Process.fork do
      reps.times do |i|
        q.write i
      end
    end

    Process.waitpid pid
    q.close

    q.join

    assert_equal reps, res.length
  end

  def test_queue_ignore_output
    num = 10
    reps = 10_000
    q = WorkQueue.new num do |obj|
      [Process.pid.to_s, obj.to_s] * " "
      :ignore
    end

    q.ignore_ouput

    res = []
    q.process do |out|
      res << out
    end

    reps.times do |i|
      q.write i
    end

    q.close
    q.join

    assert_equal 0, res.length
  end

  def test_queue_error
    5.times do |i|
      num = 20
      reps = 10_000

      q = WorkQueue.new num do |obj|
        raise ScoutException if rand < 0.1
        [Process.pid.to_s, obj.to_s] * " "
      end

      res = []
      q.process do |out|
        res << out
      end

      Log.with_severity 7 do
        t = Thread.new do
          Thread.current.report_on_exception = false
          Thread.current["name"] = "queue writer"
          reps.times do |i|
            q.write i
          end
          q.close
        end
        Thread.pass until t["name"]

        assert_raise ScoutException do
          begin
            t.join
            q.join(false)
          rescue
            t.raise($!)
            raise $!
          ensure
            t.join
            q.close
          end
        end
      end
    end
  end

  def test_queue_error_in_input
    5.times do |i|
      num = 100
      reps = 10_000

      q = WorkQueue.new num do |obj|
        [Process.pid.to_s, obj.to_s] * " "
      end

      res = []
      q.process do |out|
        raise ScoutException 
        res << out
      end

      Log.with_severity 7 do
        t = Thread.new do
          Thread.current.report_on_exception = false
          Thread.current["name"] = "queue writer"
          reps.times do |i|
            q.write i
          end
          q.close
        end
        Thread.pass until t["name"]

        assert_raise ScoutException do
          begin
            t.join
            q.join(false)
          rescue Exception
            t.raise($!)
            raise $!
          ensure
            t.join
            q.clean
          end
        end
      end
    end
  end
end

