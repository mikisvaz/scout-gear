class Step
  def abort(exception = nil)
    if (pid = info[:pid]) && pid != Process.pid && Misc.pid_alive?(pid)
      Process.kill pid
    else
      while @result && streaming? && stream = self.stream
        stream.abort(exception)
      end
    end
  end

  def recoverable_error?
    self.error? && ! (ScoutException === self.exception)
  end

  def updated?
    return false if self.error? && self.recoverable_error?
    return true if self.done? && ! ENV["SCOUT_UPDATE"]
    newer = rec_dependencies.select{|dep| Path.newer?(self.path, dep.path) }
    newer += input_dependencies.select{|dep| Path.newer?(self.path, dep.path) }

    newer.empty?
  end

  def clean
    @take_stream = nil 
    @result = nil
    @info = nil
    @info_load_time = nil
    Open.rm path if Open.exist?(path)
    Open.rm tmp_path if Open.exist?(tmp_path)
    Open.rm info_file if Open.exist?(info_file)
    Open.rm_rf files_dir if Open.exist?(files_dir)
  end


  def recursive_clean
    dependencies.each do |dep|
      dep.recursive_clean
    end
    clean
  end

end
