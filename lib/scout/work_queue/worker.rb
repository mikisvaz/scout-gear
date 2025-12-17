class WorkQueue
  class Worker
    EXIT_STATUS=246
    SIGNAL='ABRT'

    attr_accessor :pid, :ignore_ouput, :queue_id
    def initialize(ignore_ouput = false)
      @ignore_output = ignore_ouput
    end

    def worker_short_id
      [object_id, pid].compact * "@"
    end

    def worker_id
      [worker_short_id, queue_id] * "->"
    end

    def run
      @pid = Process.fork do
        Signal.trap(SIGNAL) do
          Kernel.exit! EXIT_STATUS
        end
        Signal.trap('INT') do
          Kernel.exit! -1
        end
        Log.low "Worker start #{worker_id}"
        yield
      end
    end

    def process(input, output = nil, &block)
      run do
        begin
          if output
            Open.purge_pipes(input.sread, output.swrite)
          else
            Open.purge_pipes(input.sread)
          end

          while obj = input.read
            if DoneProcessing === obj
              output.write DoneProcessing.new
              raise obj
            end
            res = block.call obj
            output.write res unless ignore_ouput || res == :ignore
          end
        rescue DoneProcessing
        rescue Interrupt
        rescue Exception
          begin
            output.write WorkerException.new($!, Process.pid)
            exit EXIT_STATUS
          rescue
            exit -1
          end
        end
        exit 0
      end
    end

    def abort
      begin
        Log.medium "Aborting worker #{worker_id}"
        Process.kill SIGNAL, @pid
      rescue Errno::ECHILD
      rescue Errno::ESRCH
      end
    end

    def join
      Log.low "Joining worker #{worker_id}"
      Process.waitpid @pid
    end

    def self.join(workers)
      workers = [workers] unless Array === workers
      begin
        while pid = Process.wait
          status = $?
            worker = workers.select{|w| w.pid == pid }.first
        end
      rescue Errno::ECHILD
      end
    end
  end
end
