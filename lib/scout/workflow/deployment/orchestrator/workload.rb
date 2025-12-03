class Workflow::Orchestrator

  def self.prepare_for_execution(job)
    rec_dependencies = job.rec_dependencies(true)

    return if rec_dependencies.empty?

    all_deps = rec_dependencies + [job]

    all_deps.each do |dep|
      begin
        dep.clean if (dep.error? && dep.recoverable_error?) ||
          dep.aborted? || (dep.done? && ! dep.updated?)
      rescue RbbtException
        Log.exception $!
        next
      end
    end
  end

  def self.job_workload(jobs)
    workload = {}
    jobs = [jobs] unless Array === jobs
    jobs.each do |job|
      workload[job] = []
      next if job.done? && job.updated?
      next if job.overrider?

      job.dependencies.each do |dep|
        next if dep.done? && dep.updated?
        next if dep.overrider?
        workload.merge!(job_workload(dep))
        workload[job] += workload[dep]
        workload[job] << dep
        workload[job].uniq!
      end

      job.input_dependencies.each do |dep|
        next if dep.done? && dep.updated?
        next if dep.overrider?
        workload.merge!(job_workload(dep))
        workload[job] += workload[dep]
        workload[job] << dep
        workload[job].uniq!
      end
    end

    workload
  end

  def self.job_dependencies(job)
    (job.dependencies + job.input_dependencies).uniq.select{|d| ! d.done? || d.dirty? }
  end

  def self.done_batch?(batch)
    top = batch[:top_level]
    top.done? || top.running? || (top.error? && ! top.recoverable_error?)
  end
end
