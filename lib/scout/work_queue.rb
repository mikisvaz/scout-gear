require_relative 'work_queue/socket'
require_relative 'work_queue/worker'
require_relative 'work_queue/exceptions'
require 'timeout'

class WorkQueue
  attr_accessor :workers, :worker_proc, :callback

  def new_worker
    worker = Worker.new
    worker.queue_id = queue_id
    worker
  end

  def initialize(workers = 0, &block)
    workers = workers.to_i if String === workers
    @input = WorkQueue::Socket.new
    @output = WorkQueue::Socket.new
    @workers = workers.times.collect{ new_worker }
    @worker_proc = block
    @worker_mutex = Mutex.new
    @removed_workers = []
    Log.medium "Starting queue #{queue_id} with workers: #{Log.fingerprint @workers.collect{|w| w.worker_short_id }} and sockets #{@input.socket_id} and #{@output.socket_id}"
  end

  def queue_id
    [object_id, Process.pid] * "@"
  end

  def add_worker(&block)
    worker = new_worker
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
      worker = @workers.index{|w| w.pid == pid}
      if worker
        @workers.delete_at(worker)
        @removed_workers << pid
        Log.low "Removed worker #{pid} from #{queue_id}"
      else
        Log.medium "Worker #{pid} not from #{queue_id}"
      end
    end
  end

  def process(&callback)
    @workers.each do |w| 
      w.process @input, @output, &@worker_proc
    end

    @reader = Thread.new(Thread.current) do |parent|
      begin
        Thread.current.report_on_exception = false
        Thread.current["name"] = "Output reader #{queue_id}"
        @done_workers ||= []
        #while true
        #  obj = @output.read
        while obj = @output.read
          if DoneProcessing === obj

            done = @worker_mutex.synchronize do
              Log.low "Worker #{obj.pid} from #{queue_id} done"
              @done_workers << obj.pid
              #@closed && (@workers.empty? || @workers.length == @removed_workers.length + @done_workers.length)
              @closed && @done_workers.length == @removed_workers.length + @workers.length
            end

            break if done
          elsif Exception === obj
            raise obj
          else
            callback.call obj if callback
          end
        end
        @waiter.join if @workers.any?
      rescue DoneProcessing
      rescue Aborted
      rescue WorkerException
        Log.error "Exception in worker #{obj.pid} in queue #{queue_id}: #{obj.worker_exception.message}"
        self.abort
        @input.abort obj.worker_exception
        raise obj.worker_exception
      rescue
        Log.error "Exception processing output in queue #{queue_id}: #{$!.message}"
        self.abort
        raise $!
      end
    end

    Thread.pass until @reader["name"]

    Thread.pass until @worker_mutex.synchronize{ @workers.select{|w| w.pid.nil? }.empty? }

    @waiter = Thread.new do
      Thread.current.report_on_exception = false
      Thread.current["name"] = "Worker waiter #{queue_id}"
      while true
        break if @worker_mutex.synchronize{ @workers.empty? }
        threads = @workers.collect do |w|
          t = Thread.new do
            Thread.report_on_exception = false
            Thread.current["name"] = "Worker waiter #{queue_id} worker #{w.pid}"
            pid, status = Process.wait2 w.pid
            remove_worker(pid) if pid
            #@output.write WorkerException.new(Exception.new("Worker ended with status #{status.exitstatus}"), pid) unless status.success?
            raise Exception.new("Worker #{pid} ended with status #{status.exitstatus}") unless (status.success? || status.exitstatus == WorkQueue::Worker::EXIT_STATUS)
          end
          Thread.pass until t["name"]
          t
        end
        exceptions = []
        threads.each do |t| 
          begin
            t.join 
          rescue
            exceptions << $!
          end
        end

        raise exceptions.first if exceptions.any?
      end
    end

    Thread.pass until @waiter["name"]
  end

  def write(obj)
    begin
      @input.write obj
    rescue Exception
      raise $! unless @input.exception
    ensure
      raise @input.exception if @input.exception
    end
  end

  def abort
    @aborted = true
    Log.low "Aborting #{@workers.length} workers in queue #{queue_id}"
    @worker_mutex.synchronize do
      @workers.each do |w| 
        ScoutSemaphore.post_semaphore(@output.write_sem)
        ScoutSemaphore.post_semaphore(@input.read_sem)
        w.abort 
      end
    end
  end

  def close
    return if @closed || @aborted
    @closed = true
    @worker_mutex.synchronize{ @workers.length }.times do
      begin
        @input.write DoneProcessing.new() unless @input.closed_write?
      rescue IOError
      end
    end
  end

  def clean
    @waiter.join if @waiter 
    @input.clean
    @output.clean
  end

  def join(clean = true)
    close
    begin
      @waiter.join if @waiter
      @reader.join if @reader
    ensure
      self.clean if clean
    end
  end
end
