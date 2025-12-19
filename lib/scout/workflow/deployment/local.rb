require_relative 'orchestrator/batches'
class Workflow::LocalExecutor
  class NoWork < Exception; end

  def self.process(*args)
    self.new.process(*args)
  end

  def self.produce(jobs, rules = {}, produce_cpus: Etc.nprocessors, produce_timer: 1)
    jobs = [jobs] unless Array === jobs
    orchestrator = self.new produce_timer.to_f, cpus: produce_cpus.to_i
    begin
      orchestrator.process(rules, jobs)
    rescue self::NoWork
    end
  end

  def self.produce_dependencies(jobs, tasks, rules = {}, produce_cpus: Etc.nprocessors, produce_timer: 1)
    jobs = [jobs] unless Array === jobs
    tasks = tasks.collect{|task| (String === task) ? task.to_sym : task }

    produce_list = []
    jobs.each do |job|
      next if job.done? || job.running?
      job.rec_dependencies.each do |dep|
        task_name = dep.task_name.to_sym
        task_name = task_name.to_sym if String === task_name
        produce_list << dep if tasks.include?(task_name) ||
          tasks.include?(job.task_name.to_s) ||
          tasks.include?(job.full_task_name)
      end
    end

    produce(produce_list, rules, produce_cpus: produce_cpus, produce_timer: produce_timer)
  end

  attr_accessor :available_resources, :resources_requested, :resources_used, :timer

  def initialize(timer = 5, available_resources = nil)
    available_resources  = {:cpus => Etc.nprocessors } if available_resources.nil?
    @timer               = timer
    @available_resources = IndiferentHash.setup(available_resources)
    @resources_requested = IndiferentHash.setup({})
    @resources_used      = IndiferentHash.setup({})
    Log.info "LocalExecutor initiated #{Log.fingerprint available_resources}"
  end

  def process_batches(batches, bar: true)
    retry_jobs = []
    failed_jobs = []

    bar = {desc: "Processing batches"} if TrueClass === bar
    bar = {bar: bar} if Log::ProgressBar === bar
    Log::ProgressBar.with_bar batches.length, bar do |bar|
      bar.init if bar

      while (missing_batches = batches.reject{|b| Workflow::Orchestrator.done_batch?(b) }).any?

        bar.pos batches.select{|b| Workflow::Orchestrator.done_batch?(b) }.length if bar

        candidates = Workflow::LocalExecutor.candidates(batches)
        top_level_jobs = candidates.collect{|batch| batch[:top_level] }

        raise NoWork, "No candidates and no running jobs #{Log.fingerprint batches}" if resources_used.empty? && top_level_jobs.empty?

        if candidates.reject{|batch| failed_jobs.include? batch[:top_level] }.empty? && resources_used.empty? && top_level_jobs.empty?
          exception = failed_jobs.collect(&:get_exception).compact.first
          if exception
            Log.warn 'Some work failed'
            raise exception
          else
            raise 'Some work failed'
          end
        end

        candidates.each do |batch|
          begin

            job = batch[:top_level]

            case
            when (job.error? || job.aborted?)
              begin
                if job.recoverable_error?
                  if retry_jobs.include?(job)
                    Log.warn "Failed twice #{job.path} with recoverable error"
                    retry_jobs.delete job
                    failed_jobs << job
                    next
                  else
                    retry_jobs << job
                    job.clean
                    raise TryAgain
                  end
                else
                  failed_jobs << job
                  Log.warn "Non-recoverable error in #{job.path}"
                  next
                end
              ensure
                Log.warn "Releases resources from failed job: #{job.path}"
                release_resources(job)
              end
            when job.done?
              Log.debug "Orchestrator done #{job.path}"
              release_resources(job)
              clear_batch(batches, batch)
              erase_job_dependencies(job, batches)
            when job.running?
              next

            else
              check_resources(batch) do
                run_batch(batch)
              end
            end
          rescue TryAgain
            retry
          end
        end

        batches.each do |batch|
          job = batch[:top_level]
          if job.done? || job.aborted? || job.error?
            job.join if job.done?
            clear_batch(batches, batch)
            release_resources(job)
            erase_job_dependencies(job, batches)
          end
        end

        sleep timer
      end
    end

    batches.each{|batch|
      job = batch[:top_level]
      begin
        job.join
      rescue
        Log.warn "Job #{job.short_path} ended with exception #{$!.class.to_s}: #{$!.message}"
      end
    }

    batches.each{|batch|
      job = batch[:top_level]
      erase_job_dependencies(job, batches) if job.done?
    }
  end

  def process(rules, jobs = nil)
    jobs, rules = rules, {} if jobs.nil?

    if Step === jobs
      jobs = [jobs]
    end

    if jobs.length == 1
      bar = jobs.first.progress_bar("Process batches for #{jobs.first.short_path}")
    else
      bar = true
    end

    batches = Workflow::Orchestrator.job_batches(rules, jobs)
    batches.each do |batch|
      rules = IndiferentHash.setup batch[:rules]
      rules.delete :erase if jobs.include?(batch[:top_level])
      resources = Workflow::Orchestrator.normalize_resources_from_rules(rules)
      resources = IndiferentHash.add_defaults resources, rules[:default_resources] if rules[:default_resources]
      batch[:resources] = resources
      batch[:rules] = rules
    end

    process_batches(batches, bar: bar)
  end

  def release_resources(job)
    if resources_used[job]
      Log.debug "Orchestrator releasing resouces from #{job.path}"
      resources_used[job].each do |resource,value|
        next if resource == 'size'
        resources_requested[resource] -= value.to_i
      end
      resources_used.delete job
    end
  end

  def check_resources(batch)
    resources = batch[:resources]
    job = batch[:top_level]

    limit_resources = resources.select do |resource,value|
      value && available_resources[resource] && ((resources_requested[resource] || 0) + value) > available_resources[resource]
    end.collect do |resource,v|
      resource
    end

    if limit_resources.any?
      Log.debug "Orchestrator waiting on #{job.path} due to #{limit_resources * ", "}"
    else

      resources_used[job] = resources
      resources.each do |resource,value|
        resources_requested[resource] ||= 0
        resources_requested[resource] += value.to_i
      end
      Log.low "Orchestrator producing #{job.path} with resources #{resources}"

      return yield
    end
  end

  def run_batch(batch)
    job, job_rules = batch.values_at :top_level, :rules

    rules = batch[:rules]
    deploy = rules[:deploy] if rules
    Log.debug "Processing #{deploy} #{job.short_path} #{Log.fingerprint job_rules}"
    case deploy
    when nil, 'local', :local, :serial, 'serial'
      Scout::Config.with_config do
        job_rules[:config_keys].split(/,\s*/).each do |config|
          Scout::Config.process_config config
        end if job_rules && job_rules[:config_keys]

        log = job_rules[:log] if job_rules
        log = Log.severity if log.nil?
        Log.with_severity log do
          job.fork(true)
        end
      end
    when 'batch', 'sched', 'slurm', 'pbs', 'lsf'
      job.init_info
      Workflow::Scheduler.process_batches([batch])
      job.join
    else
      require 'scout/offsite'
      if deploy.end_with?('-batch')
        server = deploy.sub('-batch','')
        OffsiteStep.setup(job, server: server, batch: true)
      else
        OffsiteStep.setup(job, server: deploy)
      end

      job.produce
      job.join
    end
  end

  def erase_job_dependencies(job, batches)
    all_jobs = batches.collect{|b| b[:jobs] }.flatten
    top_level_jobs = batches.collect{|b| b[:top_level] }

    job.dependencies.each do |dep|
      batch =  batches.select{|b| b[:jobs].include? dep}.first
      next unless batch
      rules = batch[:rules]
      next unless rules[:erase].to_s == 'true'

      dep_path = dep.path
      parents = all_jobs.select do |parent|
        parent.rec_dependencies.include?(dep)
      end

      next if parents.select{|parent| ! parent.done? }.any?

      parents.each do |parent|
        Log.high "Erasing #{dep.path} from #{parent.path}"
        parent.archive_deps
        parent.copy_linked_files_dir
        parent.dependencies = parent.dependencies - [dep]
      end

      dep.clean
    end
  end

  def clear_batch(batches, batch)
    job = batch[:top_level]

    parents = batches.select do |b|
      b[:deps].include? batch
    end

    parents.each{|b| b[:deps].delete batch }
  end

  #{{{ HELPER

  def self.purge_duplicates(batches)
    seen = Set.new
    batches.select do |batch|
      path = batch[:top_level].path
      if seen.include? path
        false
      else
        seen << path
        true
      end
    end
  end

  def self.sort_candidates(batches)
    seen = Set.new
    batches.sort_by do |batch|
      - batch[:resources].values.compact.select{|e| Numeric === e }.inject(0.0){|acc,e| acc += e}
    end
  end

  def self.candidates(batches)

    leaf_nodes = batches.select{|b| b[:deps].empty? }

    leaf_nodes.reject!{|b| Workflow::Orchestrator.done_batch?(b) }

    leaf_nodes = purge_duplicates leaf_nodes
    leaf_nodes = sort_candidates leaf_nodes

    leaf_nodes
  end
end
