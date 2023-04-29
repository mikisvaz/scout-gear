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
    worker = @worker_mutex.synchronize do
      Log.debug "Remove #{pid}"
      @removed_workers.concat(@workers.delete_if{|w| w.pid == pid })
    end
  end

  def process(&callback)
    @workers.each do |w| 
      w.process @input, @output, &@worker_proc
    end
    @reader = Thread.new do
      begin
        while true
          obj = @output.read
          if DoneProcessing === obj
            remove_worker obj.pid if obj.pid
          else
            callback.call obj if callback
          end
        end
      rescue Aborted
      end
    end if @output
  end

  def write(obj)
    @input.write obj
  end

  def close
    while @worker_mutex.synchronize{ @workers.length } > 0
      begin
        @input.write DoneProcessing.new
        pid = Process.wait
        status = $?
        worker = @worker_mutex.synchronize{ @removed_workers.delete_if{|w| w.pid == pid }.first }
        worker.exit $?.exitstatus if worker
      rescue Errno::ECHILD
        Thread.pass until @workers.length == 0
        break
      end
    end
    @reader.raise Aborted if @reader
  end

  def join
    @reader.join if @reader
  end
end
