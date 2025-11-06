class Workflow::Orchestrator

  def self.job_workload(jobs)
    workload = []
    path_jobs = {}

    jobs = [jobs] unless Array === jobs

    jobs.each do |job|
      path_jobs[job.path] = job
    end

    heap = []
    heap += jobs.collect(&:path)
    while job_path = heap.pop
      j = path_jobs[job_path]
      next if j.done?
      workload << j

      deps = job_dependencies(j)
      deps.each do |d|
        path_jobs[d.path] ||= d
      end

      heap.concat deps.collect(&:path)
      heap.uniq!
    end

    path_jobs
  end

  def self.job_workload(jobs)
    workload = {}
    jobs = [jobs] unless Array === jobs
    jobs.each do |job|
      workload[job] = []
      next if job.done? && job.updated?

      job.dependencies.each do |dep|
        next if dep.done? && dep.updated?
        workload.merge!(job_workload(dep))
        workload[job] += workload[dep]
        workload[job] << dep
        workload[job].uniq!
      end

      job.input_dependencies.each do |dep|
        next if dep.done? && dep.updated?
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
