require 'time'
require 'scout/config'
class Step
  SERIALIZER = Scout::Config.get(:serializer, :step_info, :info, :step, env: "SCOUT_SERIALIZER", default: :json)
  def info_file
    return nil if @path.nil?
    @info_file ||= begin
                     info_file = @path + ".info"
                     @path.annotate info_file if Path === @path
                     info_file
                   end
  end

  def self.load_info(info_file)
    info = begin
             Persist.load(info_file, SERIALIZER) || {}
           rescue
             begin
               Persist.load(info_file, :marshal) || {}
             rescue
               {status: :noinfo}
             end
           end
    IndiferentHash.setup(info)
  end

  def load_info
    @info = Step.load_info(info_file)
    @info_load_time = Time.now
  end

  def save_info(info = nil)
    purged = Annotation.purge(@info = info)
    Persist.save(purged, info_file, SERIALIZER)
    @info_load_time = Time.now
  end

  def reset_info(info = {})
    save_info(@info = info)
  end

  def init_info(status=:waiting)
    log status unless info_file.nil? || Open.exists?(info_file)
  end

  def info
    outdated = begin
                 @info_load_time && (mtime = Open.mtime(info_file)) && mtime > @info_load_time
               rescue
                 true
               end

    if @info.nil? || outdated
      load_info
    end

    @info
  end

  def pid
    info[:pid]
  end

  def pid=(pid)
    set_info :pid, pid
  end


  def merge_info(new_info)
    info = self.info
    new_info.each do |key,value|
      value = Annotation.purge(value)
      if key == :status
        message = new_info[:message]
        if message.nil? && (value == :done || value == :error || value == :aborted)
          issued = info[:issued]
          start = info[:start]
          eend = new_info[:end]

          start = Time.parse start if String === start
          eend = Time.parse eend if String === eend
          issued = Time.parse issued if String === issued

          if start && eend
            time = eend - start
            Log.warn "No issue time #{self.path}" if issued.nil?
            total_time = eend - issued
            if total_time - time > 1
              time_str = "#{Misc.format_seconds_short(time)} (#{Misc.format_seconds_short(total_time)})"
            else
              time_str = Misc.format_seconds_short(time)
            end
            info[:time_elapsed] = time
            info[:total_time_elapsed] = total_time
            message = Log.color(:time, time_str)
          end
        end
        report_status value, message
      end

      if key == :message
        messages = info[:messages] || []
        messages << value
        info[:messages] = messages
        next
      end

      if Exception === value
        begin
          Marshal.dump(value)
        rescue TypeError
          if ScoutException === value
            new = ScoutException.new value.message
          else
            new = Exception.new value.message
          end
          new.set_backtrace(value.backtrace)
          value = new
        end
      end

      if info.include?(key)
        case info[key]
        when Array
          info[key].concat(Array === value ? value : [value])
        when Hash
          info[key].merge! value
        else
          info[key] = value
        end
      else
        info[key] = value
      end
    end
    save_info(info)
  end

  def set_info(key, value)
    merge_info(key => value)
  end

  def report_status(status, message = nil)
    if message.nil?
      Log.info [Log.color(:status, status, true), Log.color(:task, task_name, true), Log.color(:path, path)] * " "
    else
      message = Log.fingerprint(message.split("\n").first).sub(/^'/,'').sub(/'$/,'')
      Log.info [Log.color(:status, status, true), Log.color(:task, task_name, true), message, Log.color(:path, path)] * " "
    end
  end

  def log(status, message = nil, &block)
    if block_given?
      time = Misc.exec_time &block
      time_str = Misc.format_seconds_short time
      message = message.nil? ? Log.color(:time, time_str) : "#{Log.color :time, time_str} - #{ message }"
    end

    if message
      merge_info :status => status, :message => message
    else
      merge_info :status => status
    end
  end

  def messages
    info[:messages]
  end

  def message(message)
    merge_info :message => message
  end

  def status
    info[:status].tap{|s| s.nil? ? s : s.to_sym }
  end

  def error?
    status == :error || status == 'error'
  end

  def aborted?
    status == :aborted || status == 'aborted'
  end

  def running?
    ! (done? && status == :done) && (info[:pid] && Misc.pid_alive?(info[:pid]))
  end

  def exception
    return nil unless info[:exception]
    begin
      Marshal.load(Base64.decode64(info[:exception]))
    rescue
      Log.exception $!
      return Exception.new messages.last
    end
  end

  # Marshal Step
  def _dump(level)
    @path
  end

  def self._load(path)
    Step.new path
  end

  def marshal_load(path)
    Step.new path
  end
end
