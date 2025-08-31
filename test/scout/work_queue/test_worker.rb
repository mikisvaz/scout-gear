require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/semaphore'
require 'scout/work_queue/socket'
class TestQueueWorker < Test::Unit::TestCase
  def test_simple
    worker = WorkQueue::Worker.new
    TmpFile.with_file do |file|
      worker.run do
        Open.write file, "TEST"
      end
      worker.join

      assert_equal "TEST", Open.read(file)
    end
  end

  def test_semaphore_pipe

    2.times do
      num_lines = 10
      num_workers = 100

      TmpFile.with_file do |outfile|
        Open.rm(outfile)
        ScoutSemaphore.with_semaphore 1 do |sem|
          sout = Open.open_pipe do |sin|
            workers = num_workers.times.collect{ WorkQueue::Worker.new }
            workers.each do |w|
              w.run do
                ScoutSemaphore.synchronize(sem) do
                  sin.puts "Start - #{Process.pid}"
                  num_lines.times do |i|
                    sin.puts "line-#{i}-#{Process.pid}"
                  end
                  sin.puts "End - #{Process.pid}"
                end
              end
            end
            sin.close

            WorkQueue::Worker.join(workers)
          end

          Open.consume_stream(sout, false, outfile)
          txt = Open.read(outfile)
          pid_list = txt.split("\n")
          
          assert_equal (num_lines + 2) * num_workers, pid_list.length

          assert_nothing_raised do
            seen = []
            current = nil
            pid_list.each do |pid|
              if pid != current
                raise "Out of order #{Log.fingerprint seen} #{ pid }" if seen.include? pid
              end
              current = pid
              seen << pid
            end
          end
        end
      end
    end
  end
  def test_semaphore

    2.times do
      num_lines = 10
      num_workers = 500

      TmpFile.with_file do |outfile|
        Open.rm(outfile)
        ScoutSemaphore.with_semaphore 1 do |sem|
          workers = num_workers.times.collect{ WorkQueue::Worker.new }
          Open.touch(outfile)
          workers.each do |w|
            w.run do
              ScoutSemaphore.synchronize(sem) do
                sin = Open.open(outfile, :mode => 'a')
                sin.puts "Start - #{Process.pid}"
                  num_lines.times do |i|
                    sin.puts "line-#{i}-#{Process.pid}"
                  end
                sin.puts "End - #{Process.pid}"
                sin.close
              end
            end
          end

          WorkQueue::Worker.join(workers)


          pid_list = Open.read(outfile).split("\n")
          assert_equal (num_lines + 2) * num_workers, pid_list.length

          assert_nothing_raised do
            seen = []
            current = nil
            pid_list.each do |pid|
              if pid != current
                raise "Out of order #{Log.fingerprint seen} #{ pid }" if seen.include? pid
              end
              current = pid
              seen << pid
            end
          end
        end
      end
    end
  end

  def test_process
    input = WorkQueue::Socket.new
    output = WorkQueue::Socket.new

    workers = 10.times.collect{ WorkQueue::Worker.new }
    workers.each do |w|
      w.process(input, output) do |obj|
        [Process.pid, obj.inspect] * " "
      end
    end

    read = Thread.new do 
      begin
        while obj = output.read
          if DoneProcessing === obj
            pid = obj.pid
            workers.delete_if{|w| w.pid = pid }
            break if workers.empty?
          end
        end
      end
    end

    write = Thread.new do
      100.times do |i|
        input.write i
      end
      10.times do
        input.write DoneProcessing.new
      end
      input.close_write
    end

    write.join
    read.join

    WorkQueue::Worker.join workers
    input.clean
    output.clean
  end

  def test_process_exception
    input = WorkQueue::Socket.new
    output = WorkQueue::Socket.new

    workers = 5.times.collect{ WorkQueue::Worker.new }
    workers.each do |w|
      w.process(input, output) do |obj|
        raise ScoutException
        [Process.pid, obj.inspect] * " "
      end
    end

    Open.purge_pipes(input.swrite, output.sread)
    read = Thread.new do
      Thread.current.report_on_exception = false
      while obj = output.read
        if DoneProcessing === obj
          pid = obj.pid
          @worker_mutex.synchronize{ @workers.delete_if{|w| w.pid = pid } }
          break if workers.empty?
        end
        raise obj if Exception === obj
      end
    ensure
      output.close_read
    end

    write = Thread.new do
      Thread.report_on_exception = false
      100.times do |i|
        input.write i
      end
      10.times do
        input.write DoneProcessing.new
      end
      input.close_write
    rescue
    end

    write.join

    assert_raise WorkerException do
      read.join
    end

    WorkQueue::Worker.join workers
    input.clean
    output.clean
  end

end

