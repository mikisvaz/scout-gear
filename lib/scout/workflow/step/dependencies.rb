class Step
  def rec_dependencies(connected = false, seen = [])
    @rec_dependencies = {}
    @rec_dependencies[connected] ||= begin
                            direct_deps = []
                            dependencies.each do |dep|
                              next if seen.include? dep.path
                              next if connected && dep.done? && dep.updated?
                              direct_deps << dep
                            end if dependencies
                            seen.concat direct_deps.collect{|d| d.path }
                            seen.uniq!
                            direct_deps.inject(direct_deps){|acc,d| acc.concat(d.rec_dependencies(connected, seen)); acc }
                            direct_deps.uniq!
                            direct_deps
                          end
  end

  def recursive_inputs
    recursive_inputs = NamedArray === inputs ? inputs.to_hash : {}
    return recursive_inputs if dependencies.nil?
    dependencies.inject(recursive_inputs) do |acc,dep|
      acc = dep.recursive_inputs.merge(acc)
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

    dependencies.each do |dep|
      if dep.present? && ! dep.updated?
        Log.medium "Clean outdated #{dep.path}"
        dep.clean
      end

      next if dep.done?
      next if dep.error? && ! dep.recoverable_error?

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
    end if dependencies

    inverse_dep.each do |dep,list|
      dep.tee_copies = list.length
    end
  end

  def all_dependencies
    @all_dependencies ||= begin
                            all_dependencies = []
                            all_dependencies += dependencies if dependencies
                            all_dependencies += input_dependencies if input_dependencies
                            all_dependencies
                          end
  end

  def run_dependencies
    all_dependencies.each do |dep| 
      next if dep.running? || dep.done?
      next if dep.error? && ! dep.recoverable_error?

      compute_options = compute[dep.path] if compute
      compute_options = [] if compute_options.nil?

      next if compute_options.include?(false)

      stream = compute_options.include?(:stream)
      stream = true unless ENV["SCOUT_EXPLICIT_STREAMING"] == 'true'
      stream = :no_load if compute_options.include?(:produce)

      begin
        dep.run(stream)
      rescue ScoutException
        if compute_options.include?(:canfail)
          Log.medium "Allow failing of #{dep.path}"
        else
          raise $!
        end
      end
    end
  end

  def abort_dependencies
    all_dependencies.each{|dep| dep.abort if dep.running? } 
  end

  def self.wait_for_jobs(jobs, canfail=false)
    threads = []
    jobs.each do |job|
      threads << Thread.new do
        Thread.current.report_on_exception = false
        begin
          job.join
        rescue Exception
          case canfail
          when TrueClass
            next
          else
            if canfail === $!
              next
            else
              raise $!
            end
          end
        end
      end
    end
    threads.each do |t|
      t.join
    end
  end
end
