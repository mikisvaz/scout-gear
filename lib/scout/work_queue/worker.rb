class WorkQueue
  class Worker
    attr_accessor :pid, :ignore_ouput
    def initialize(ignore_ouput = false)
      @ignore_output = ignore_ouput
    end

    def run
      @pid = Process.fork do
        Log.debug "Worker start with #{Process.pid}"
        yield
      end
    end

    def process(input, output = nil, &block)
      run do
        begin
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
          output.write WorkerException.new($!, Process.pid)
          exit -1
        ensure
        end
        exit 0
      end
    end

    def abort
      begin
        Log.debug "Aborting worker #{@pid}"
        Process.kill "INT", @pid 
      rescue Errno::ECHILD 
      rescue Errno::ESRCH
      end
    end

    def join
      Log.debug "Joining worker #{@pid}"
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
