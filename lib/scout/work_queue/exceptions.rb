class DoneProcessing < Exception
  attr_accessor :pid
  def initialize(pid = Process.pid)
    @pid = pid
  end

  def message
    "Done processing pid #{pid}"
  end
end

class WorkerException < ScoutException
  attr_accessor :worker_exception, :pid
  def initialize(worker_exception, pid)
    @worker_exception = worker_exception
    @pid = pid
  end
end
