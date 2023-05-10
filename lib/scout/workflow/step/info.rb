class Step
  SERIALIZER = :marshal
  def info_file
    @info_file ||= begin
                     info_file = @path + ".info"
                     @path.annotate info_file if Path === @path
                     info_file
                   end
  end

  def load_info
    @info = Persist.load(info_file, SERIALIZER) || {}
    IndiferentHash.setup(@info)
    @info_load_time = Time.now
  end

  def save_info(info = nil)
    Persist.save(info, info_file, SERIALIZER)
    @info_load_time = Time.now
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

  def merge_info(new_info)
    info = self.info
    new_info.each do |key,value|
      report_status new_info[:status], new_info[:message] if key == :status
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
          info[key].concat Array === value ? value : [value]
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
      Log.info Log.color(:status, status, true) + " " + Log.color(:path, path)
    else
      Log.info Log.color(:status, status, true) + " " + Log.color(:path, path) + " " + message
    end
  end

  def log(status, message = nil)
    if message
      merge_info :status => status, :messages => [message]
    else
      merge_info :status => status
    end
  end

  def status
    info[:status].tap{|s| s.nil? ? s : s.to_sym }
  end

  def error?
    status == :error
  end

  def aborted?
    status == :aborted
  end

  def running?
    ! done? && (info[:pid] && Misc.pid_alive?(info[:pid]))
  end

  def exception
    info[:exception]
  end
end
