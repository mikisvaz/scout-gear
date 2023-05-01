require_relative 'work_queue/socket'
require_relative 'work_queue/worker'

class WorkQueue
  attr_accessor :workers, :worker_proc, :callback

  def initialize(workers = 0, &block)
    @input = WorkQueue::Socket.new
    @output = WorkQueue::Socket.new
    @workers = workers.times.collect{ Worker.new }
    @worker_proc = block
    @worker_mutex = Mutex.new
    @removed_workers = []
  end

  def add_worker(&block)
    worker = Worker.new
    @worker_mutex.synchronize do
      @workers.push(worker)
      if block_given?
        worker.process @input, @output, &block
      else
        worker.process @input, @output, &@worker_proc
      end
    end
    worker
  end

  def ignore_ouput
    @workers.each{|w| w.ignore_ouput = true }
  end

  def remove_one_worker
    @input.write DoneProcessing.new
  end

  def remove_worker(pid)
    @worker_mutex.synchronize do
      @workers.delete_if{|w| w.pid == pid }
      @removed_workers << pid
    end
  end

  def process(&callback)
    @reader = Thread.new do |parent|
      begin
        Thread.current.report_on_exception = false
        Thread.current["name"] = "Output reader #{Process.pid}"
        @done_workers ||= []
        while true
          obj = @output.read
          if DoneProcessing === obj
            done = @worker_mutex.synchronize do
              Log.low "Worker #{obj.pid} done"
              @done_workers << obj.pid
              @done_workers.length == @removed_workers.length + @workers.length
            end
            break if done
          elsif Exception === obj
            raise obj
          else
            callback.call obj if callback
          end
        end
      rescue DoneProcessing
      rescue Aborted
      rescue WorkerException
        Log.error "Exception in worker #{obj.pid} #{Log.fingerprint obj.exception}"
        self.abort
        raise obj.exception
      end
    end

    @workers.each do |w| 
      w.process @input, @output, &@worker_proc
    end

    Thread.pass until @reader["name"]

    @waiter = Thread.new do
      begin
        Thread.current.report_on_exception = false
        Thread.current["name"] = "Worker waiter #{Process.pid}"
        while true
          pid = Process.wait
          remove_worker(pid)
          break if workers.empty?
        end
      end
    end

    Thread.pass until @waiter["name"]
  end

  def write(obj)
    @input.write obj
  end

  def abort
    workers.each{|w| w.abort }
  end

  def close
    @worker_mutex.synchronize{ @workers.length }.times do
      @input.write DoneProcessing.new()
    end
  end

  def join
    @waiter.join if @waiter
    @reader.join if @reader
  end
end
