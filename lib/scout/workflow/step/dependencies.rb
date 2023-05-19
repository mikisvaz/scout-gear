class Step
  def rec_dependencies
    rec_dependencies = dependencies.dup
    dependencies.inject(rec_dependencies){|acc,d| acc.concat d.dependencies }
  end

  def recursive_inputs
    recursive_inputs = @inputs.to_hash
    dependencies.inject(recursive_inputs) do |acc,dep|
      acc.merge(dep.recursive_inputs)
    end
  end

  def input_dependencies
    return [] unless inputs
    inputs.select do |d|
      Step === d
    end
  end

  def prepare_dependencies
    inverse_dep = {}
    dependencies.each{|dep| 
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
    dependencies.each{|dep| dep.run unless dep.running? || dep.done? }
  end

  def self.wait_for_jobs(jobs)
    threads = []
    jobs.each do |job| 
      threads << job.join
    end
    threads.each do |t| t.join end
  end
end
