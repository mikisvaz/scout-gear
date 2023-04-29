class WorkQueue
  class Worker
    attr_accessor :pid, :ignore_ouput
    def initialize
    end

    def run
      @pid = Process.fork do
        yield
      end
    end

    def process(input, output, &block)
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
          Log.log "Worker #{Process.pid} done"
        rescue Exception
          Log.exception $!
          exit -1
        end
      end
    end

    def join
      Log.log "Joining worker #{@pid}"
      Process.waitpid @pid
    end

    def exit(status)
      Log.log "Worker #{@pid} exited with status #{Log.color(:green, status)}"
    end

    def self.join(workers)
      workers = [workers] unless Array === workers
      begin
        while pid = Process.wait 
          status = $?
          worker = workers.select{|w| w.pid == pid }.first
          worker.exit status.exitstatus if worker
        end
      rescue Errno::ECHILD
      end
    end
  end
end
