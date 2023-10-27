class Step
  SERIALIZER = :marshal
  def info_file
    return nil if @path.nil?
    @info_file ||= begin
                     info_file = @path + ".info"
                     @path.annotate info_file if Path === @path
                     info_file
                   end
  end

  def self.load_info(info_file)
    info = Persist.load(info_file, SERIALIZER) || {}
    IndiferentHash.setup(info)
  end

  def load_info
    @info = Step.load_info(info_file)
    @info_load_time = Time.now
  end



  def save_info(info = nil)
    Persist.save(info, info_file, SERIALIZER)
    @info_load_time = Time.now
  end

  def clear_info
    save_info(@info = {})
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
      value = MetaExtension.purge(value)
      if key == :status
        message = new_info[:message]
        if message.nil? && (value == :done || value == :error || value == :aborted)
          start = info[:start]
          eend = new_info[:end]
          if start && eend
            time = eend - start
            time_str = Misc.format_seconds_short(time)
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
      Log.info [Log.color(:status, status, true), Log.color(:task, task_name, true), Log.color(:path, path)] * " "
    else
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
    ! done? && (info[:pid] && Misc.pid_alive?(info[:pid]))
  end

  def overriden?
    overriden_task || overriden_workflow || dependencies.select{|d| d.overriden? }.any?
  end

  def overriden_deps
    rec_dependencies.select{|d| d.overriden? }
  end

  def exception
    info[:exception]
  end

  def marshal_dump
    @path
  end

  def marshal_load(path)
    Step.new path
  end
end
