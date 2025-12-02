class Step
  def abort(exception = nil)
    if (pid = info[:pid]) && pid != Process.pid && Misc.pid_alive?(pid)
      Log.debug "Kill process #{pid} to abort step #{Log.fingerprint self}"
      begin
        s = Misc.abort_child pid, true
        Log.medium "Aborted pid #{path} #{s}"
      rescue 
        Log.debug("Aborted job #{pid} was not killed: #{$!.message}")
      end
    else
      while @result && streaming? && stream = self.stream
        stream.abort(exception)
      end
      @take_stream.abort(exception) if streaming?
    end
  end

  def recoverable_error?
    self.error? && ! (ScoutException === self.exception)
  end

  def newer_dependencies
    rec_dependencies = self.rec_dependencies
    newer = rec_dependencies.select{|dep| Path.newer?(self.path, dep.path) }
    newer += input_dependencies.select{|dep| Path.newer?(self.path, dep.path) }
    newer += rec_dependencies.collect{|dep| dep.input_dependencies }.flatten.select{|dep| Path.newer?(self.path, dep.path) }
    newer
  end

  def cleaned_dependencies
    return []
    rec_dependencies = self.rec_dependencies
    cleaned = rec_dependencies.select{|dep| dep.info[:status] == :cleaned }
    cleaned += input_dependencies.select{|dep| dep.info[:status] == :cleaned }
    cleaned += rec_dependencies.collect{|dep| dep.input_dependencies }.flatten.select{|dep| dep.info[:status] == :cleaned }
    cleaned
  end

  def updated?
    return false if self.error? && self.recoverable_error?
    return true if (self.done? || (self.error? && ! self.recoverable_error?)) && ! ENV["SCOUT_UPDATE"]
    newer = newer_dependencies
    cleaned = cleaned_dependencies

    Log.low "Newer deps found for #{Log.fingerprint self}: #{Log.fingerprint newer}" if newer.any?
    Log.low "Cleaned deps found for #{Log.fingerprint self}: #{Log.fingerprint cleaned}" if cleaned.any?
    newer.empty? && cleaned.empty?
  end

  def clean
    Log.debug "Cleaning job files: #{path}"
    @take_stream = nil 
    @result = nil
    @info = nil
    @info_load_time = nil
    @done = nil
    Open.rm path if Open.exist_or_link?(path)
    Open.rm tmp_path if Open.exist_or_link?(tmp_path)
    Open.rm info_file if Open.exist_or_link?(info_file)
    Open.rm_rf files_dir if Open.exist_or_link?(files_dir)
    self
  end

  def self.clean(file)
    Step.new(file).clean
  end


  def recursive_clean
    dependencies.each do |dep|
      dep.recursive_clean
    end
    clean
  end

  def canfail?
    @compute && @compute[self.path] && @compute[self.path].include?(:canfail)
  end

  def started?
    return true if done?
    return false unless Open.exist?(info_file)
    pid = info[:pid]
    return false unless pid
    return Misc.pid_alive?(pid)
  end

  def waiting?
    present? and not started?
  end

  def dirty?
    done? && ! updated?
  end
end
