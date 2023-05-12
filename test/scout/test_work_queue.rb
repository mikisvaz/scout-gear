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

    Process.wait pid
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
    num = 100
    reps = 10_000

    sss 0
    q = WorkQueue.new num do |obj|
      raise ScoutException if rand < 0.1
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

    assert_raise ScoutException do
      q.join
      t.join
    end
  end

  def test_queue_error_in_input
    num = 100
    reps = 10_000

    q = WorkQueue.new num do |obj|
      [Process.pid.to_s, obj.to_s] * " "
    end

    res = []
    q.process do |out|
      raise ScoutException if rand < 0.01
      res << out
    end

    pid = Process.fork do
      reps.times do |i|
        q.write i
      end
      q.close
    end

    assert_raise ScoutException do
      q.join
      t.join
    end
  end
end

