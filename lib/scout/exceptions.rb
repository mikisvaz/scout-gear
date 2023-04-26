class ScoutDeprecated < StandardError; end
class ScoutException < StandardError; end

class FieldNotFoundError < StandardError;end

class TryAgain < StandardError; end
class StopInsist < Exception
  attr_accessor :exception
  def initialize(exception)
    @exception = exception
  end
end

class Aborted < StandardError; end

class ParameterException < ScoutException; end
class MissingParameterException < ParameterException
  def initialize(parameter)
    super("Missing parameter '#{parameter}'")
  end
end
class ProcessFailed < StandardError; 
  attr_accessor :pid, :msg
  def initialize(pid = Process.pid, msg = nil)
    @pid = pid
    @msg = msg
    if @pid
      if @msg
        message = "Process #{@pid} failed - #{@msg}"
      else
        message = "Process #{@pid} failed"
      end
    else
      message = "Failed to run #{@msg}"
    end
    super(message)
  end
end

class ConcurrentStreamProcessFailed < ProcessFailed
  attr_accessor :concurrent_stream
  def initialize(pid = Process.pid, msg = nil, concurrent_stream = nil)
    super(pid, msg)
    @concurrent_stream = concurrent_stream
  end
end

class OpenURLError < StandardError; end

class DontClose < Exception
  attr_accessor :payload
  def initialize(payload = nil)
    @payload = payload
  end
end


class KeepLocked < Exception
  attr_accessor :payload
  def initialize(payload)
    @payload = payload
  end
end

class KeepBar < Exception
  attr_accessor :payload
  def initialize(payload)
    @payload = payload
  end
end

class LockInterrupted < TryAgain; end

#
#class ClosedStream < StandardError; end
#class OpenGzipError < StandardError; end
#
#
#class TryThis < StandardError
#  attr_accessor :payload
#  def initialize(payload = nil)
#    @payload = payload
#  end
#end
#
#class SemaphoreInterrupted < TryAgain; end
#
#class RemoteServerError < StandardError; end
#
#class DependencyError < Aborted
#  def initialize(msg)
#    if defined? Step and Step === msg
#      step = msg
#      new_msg = [step.path, step.messages.last] * ": "
#      super(new_msg)
#    else
#      super(msg)
#    end
#  end
#end
#
#class DependencyScoutException < ScoutException
#  def initialize(msg)
#    if defined? Step and Step === msg
#      step = msg
#
#      new_msg = nil
#      new_msg = [step.path, step.messages.last] * ": "
#
#      super(new_msg)
#    else
#      super(msg)
#    end
#  end
#end
#
#
#
#
