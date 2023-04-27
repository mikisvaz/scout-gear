class Step
  def info_file
    @info_file ||= @path + ".info"
  end

  def load_info
    @info = Persist.load(info_file, :marshal) || {}
    @info_load_time = Time.now
  end

  def save_info
    Persist.save(@info, info_file, :marshal)
    @info_load_time = Time.now
  end

  def info
    outdated = @info && Open.exists?(info_file) && @info_load_time && Open.mtime(info_file) > @info_load_time

    if @info.nil? || outdated
      load_info
    end

    @info
  end

  def merge_info(new_info)
    info = self.info
    new_info.each do |key,value|
      report_status new_info[:status], new_info[:message] if key == :status
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
    save_info
  end

  def set_info(key, value)
    merge_info(key => value)
  end
  
  def init_info
    @info = {
      :status => :waiting
    }
  end

  def report_status(status, message = nil)
    if message.nil?
      Log.info Log.color(:green, status.to_s) + " " + Log.color(:blue, path)
    else
      Log.info Log.color(:green, status.to_s) + " " + Log.color(:blue, path) + " " + message
    end
  end

  def log(status, message = nil)
    report_status status, message
    if message
      merge_info :status => status, :messages => [message]
    else
      merge_info :status => status
    end
  end

  def status
    info[:status]
  end

end
