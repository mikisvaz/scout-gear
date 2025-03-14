require 'scout/tsv'

module Workflow
  def self.trace_job_times(jobs, fix_gap = false, report_keys = nil)
    data = TSV.setup({}, "Job~Code,Workflow,Task,Start,End#:type=:list")
    min_start = nil
    max_done = nil
    jobs.each do |job|
      next unless job.info[:end]
      started = job.info[:start]
      ddone = job.info[:end]

      started = Time.parse started if String === started
      ddone = Time.parse ddone if String === ddone

      code = [job.workflow.name, job.task_name].compact.collect{|s| s.to_s} * " · "
      code = job.name + " - " + code

      data[job.path] = [code, job.workflow.name, job.task_name, started, ddone]
      if min_start.nil?
        min_start = started
      else
        min_start = started if started < min_start
      end

      if max_done.nil?
        max_done = ddone
      else
        max_done = ddone if ddone > max_done
      end
    end

    data.add_field "Start.second" do |k,value|
      value["Start"] - min_start
    end

    data.add_field "End.second" do |k,value|
      value["End"] - min_start
    end

    if fix_gap
      ranges = []
      data.through do |k,values|
        start, eend = values.values_at "Start.second", "End.second"

        ranges << (start..eend)
      end

      gaps = {}
      last = nil
      Misc.collapse_ranges(ranges).each do |range|
        start = range.begin
        eend = range.end
        if last
          gaps[last] = start - last
        end
        last = eend
      end

      data.process "End.second" do |value,k,values|
        gap = Misc.sum(gaps.select{|pos,size| pos < values["Start.second"]}.collect{|pos,size| size})
        value - gap
      end

      data.process "Start.second" do |value,k,values|
        gap = Misc.sum(gaps.select{|pos,size| pos < values["Start.second"]}.collect{|pos,size| size})
        value - gap
      end

      total_gaps = Misc.sum(gaps.collect{|k,v| v})
      Log.info "Total gaps: #{total_gaps} seconds"
    end

    if report_keys && report_keys.any?
      job_keys = {}
      jobs.each do |job|
        job_info = IndiferentHash.setup(job.info)
        report_keys.each do |key|
          job_keys[job.path] ||= {}
          job_keys[job.path][key] = job_info[key]
        end
      end
      report_keys.each do |key|
        data.add_field Misc.humanize(key) do |p,values|
          job_keys[p][key]
        end
      end
    end

    start = data.column("Start.second").values.flatten.collect{|v| v.to_f}.min
    eend = data.column("End.second").values.flatten.collect{|v| v.to_f}.max
    total = eend - start unless eend.nil? || start.nil?
    Log.info "Total time elapsed: #{total} seconds" if total

    if report_keys && report_keys.any?
      job_keys = {}
      report_keys.each do |key|
        jobs.each do |job|
          job_keys[job.path] ||= {}
          job_keys[job.path][key] = job.info[key]
        end
      end
      report_keys.each do |key|
        data.add_field Misc.humanize(key) do |p,values|
          job_keys[p][key]
        end
      end
    end

    data
  end

  def self.trace_job_summary(jobs, report_keys = [])
    tasks_info = {}

    report_keys = report_keys.collect{|k| k.to_s}

    jobs.each do |dep|
      next unless dep.info[:end]
      task = [dep.workflow.name, dep.task_name].compact.collect{|s| s.to_s} * "#"
      info = tasks_info[task] ||= IndiferentHash.setup({})
      dep_info = IndiferentHash.setup(dep.info)

      ddone = dep_info[:end]
      started = dep_info[:start]

      started = Time.parse started if String === started
      ddone = Time.parse ddone if String === ddone

      time = ddone - started
      info[:time] ||= []
      info[:time] << time

      report_keys.each do |key|
        info[key] = dep_info[key] 
      end

      dep.info[:config_keys].each do |kinfo| 
        key, value, tokens = kinfo

        info[key.to_s] = value if report_keys.include? key.to_s
      end if dep.info[:config_keys]
    end

    summary = TSV.setup({}, "Task~Calls,Avg. Time,Total Time#:type=:list")

    tasks_info.each do |task, info|
      time_lists = info[:time]
      avg_time = Misc.mean(time_lists).to_i
      total_time = Misc.sum(time_lists).to_i
      calls = time_lists.length
      summary[task] = [calls, avg_time, total_time]
    end

    report_keys.each do |key|
      summary.add_field Misc.humanize(key) do |task|
        tasks_info[task][key]
      end
    end if Array === report_keys && report_keys.any?

    summary
  end

  def self.trace(seed_jobs, options = {})
    jobs = []
    seed_jobs.each do |step|
      jobs += step.rec_dependencies.to_a + [step]
      step.info[:archived_info].each do |path,ainfo|
        next unless Hash === ainfo
        archived_step = Step.new path

        archived_step.define_singleton_method :info do
          ainfo
        end

        jobs << archived_step
      end if step.info[:archived_info]

    end

    jobs = jobs.uniq.sort_by{|job| [job, job.info]; t = job.info[:started] || Open.mtime(job.path) || Time.now; Time === t ? t : Time.parse(t) }

    report_keys = options[:report_keys] || ""
    report_keys = report_keys.split(/,\s*/) if String === report_keys

    data = trace_job_times(jobs, options[:fix_gap], report_keys)

    summary = trace_job_summary(jobs, report_keys)


    raise "No jobs to process" if data.size == 0

    size, width, height = options.values_at :size, :width, :height

    size = 800 if size.nil?
    width = size.to_i * 2 if width.nil?
    height = size  if height.nil?

    if options[:plot_data]
      data
    else
      summary
    end
  end
end
