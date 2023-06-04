class Step
  def rec_dependencies
    rec_dependencies = dependencies.dup
    dependencies.inject(rec_dependencies){|acc,d| acc.concat d.rec_dependencies }
  end

  def recursive_inputs
    recursive_inputs = @inputs.to_hash
    dependencies.inject(recursive_inputs) do |acc,dep|
      acc.merge(dep.recursive_inputs)
    end
  end

  def input_dependencies
    return [] unless inputs
    inputs.collect do |d|
      if Step === d
        d
      elsif (Path === d) && (Step === d.pkgdir)
        d.pkgdir
      else
        nil
      end
    end.compact.uniq
  end

  def prepare_dependencies
    inverse_dep = {}
    dependencies.each{|dep|
      if dep.present? && ! dep.updated?
        Log.debug "Clean outdated #{dep.path}"
        dep.clean
      end
      next if dep.done?
      if dep.dependencies
        dep.dependencies.each do |d|
          inverse_dep[d] ||= []
          inverse_dep[d] << dep
        end
      end
      input_dependencies.each do |d|
        inverse_dep[d] ||= []
        inverse_dep[d] << dep
      end
    }
    inverse_dep.each do |dep,list|
      dep.tee_copies = list.length
    end
  end

  def run_dependencies
    dependencies.each{|dep| 
      next if dep.running? || dep.done?
      compute_options = compute[dep.path] if compute
      compute_options = [] if compute_options.nil?

      stream = compute_options.include?(:stream)
      stream = true unless ENV["SCOUT_EXPLICIT_STREAMING"] == 'true'
      stream = false if compute_options.include?(:produce)

      begin
        dep.run(stream)
      rescue ScoutException
        if compute_options.include?(:canfail)
          Log.medium "Allow failing of #{dep.path}"
        else
          raise $!
        end
      end
    }
  end

  def abort_dependencies
    dependencies.each{|dep| dep.abort if dep.running? }
  end

  def self.wait_for_jobs(jobs)
    threads = []
    jobs.each do |job|
      threads << Thread.new{ job.join }
    end
    threads.each do |t|
      t.join
    end
  end
end
