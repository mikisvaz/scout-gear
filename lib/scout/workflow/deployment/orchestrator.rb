module Workflow
  class Orchestrator

    class NoWork < Exception; end

    def self.job_workload(job)
      workload = {job => []}
      return workload if job.done? && job.updated?

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

      workload
    end

    def self.workload(jobs)
      jobs.inject({}) do |acc,job| 
        Orchestrator.job_workload(job).each do |j,d|
          acc[j] = d unless acc.keys.collect{|k| k.path }.include? j.path
        end
        acc
      end
    end

    def self.job_rules(rules, job)
      IndiferentHash.setup(rules)
      workflow = job.workflow.name
      task_name = job.task_name.to_s
      defaults = rules["defaults"] || {}

      return IndiferentHash.setup(defaults) unless rules[workflow]
      workflow_rules = IndiferentHash.setup(rules[workflow])
      return IndiferentHash.setup(defaults) unless workflow_rules[task_name]
      job_rules = IndiferentHash.setup(workflow_rules[task_name])

      defaults.each{|k,v| job_rules[k] = v if job_rules[k].nil? } if defaults
      job_rules
    end

    def self.purge_duplicates(candidates)
      seen = Set.new
      candidates.select do |job|
        if seen.include? job.path
          false
        else
          seen << job.path
          true
        end
      end
    end

    def self.job_resources(rules, job)
      resources = (job_rules(rules, job) || {})["resources"] || {}

      IndiferentHash.setup(resources)

      default_resources = rules["default_resources"] 
      default_resources ||= rules["defaults"]["resources"] if rules["defaults"]
      default_resources ||= {}

      default_resources.each{|k,v| resources[k] ||= v } if default_resources

      resources = {:cpus => 1} if resources.empty?
      resources
    end

    def self.sort_candidates(candidates, rules)
      seen = Set.new
      candidates.sort_by do |job|
        - job_resources(rules, job).values.inject(0){|acc,e| acc += e}
      end
    end

    def self.candidates(workload, rules)
      if rules.empty?
        candidates = workload.
          select{|k,v| v.empty? }.
          collect{|k,v| k }.
          reject{|k| k.done? || k.running? || (k.error? && ! k.recoverable_error?) }
      else
        candidates = workload. #select{|k,v| Orchestrator.job_rules(rules, k) }.
          select{|k,v| v.empty? }.
          collect{|k,v| k }.
          reject{|k| k.done? || k.running? }
      end

      #top_level = workload.keys - workload.values.flatten

      candidates = purge_duplicates candidates
      candidates = sort_candidates candidates, rules

      candidates
    end

    def self.process(*args)
      self.new.process(*args)
    end

    attr_accessor :available_resources, :resources_requested, :resources_used, :timer

    def initialize(timer = 5, available_resources = nil)
      available_resources  = {:cpus => Etc.nprocessors } if available_resources.nil?
      @timer               = timer
      @available_resources = IndiferentHash.setup(available_resources)
      @resources_requested = IndiferentHash.setup({})
      @resources_used      = IndiferentHash.setup({})
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

    def check_resources(rules, job)
      resources = Orchestrator.job_resources(rules, job)

      limit_resources = resources.select{|resource,value| available_resources[resource] && ((resources_requested[resource] || 0) + value) > available_resources[resource]  }.collect{|resource,v| resource }
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

    def run_with_rules(rules, job)
      job_rules = Orchestrator.job_rules(rules, job)

      Scout::Config.with_config do 
        job_rules[:config_keys].each do |config|
          Scout::Config.process_config config
        end if job_rules && job_rules[:config_keys]

        log = job_rules[:log] if job_rules 
        log = Log.severity if log.nil?
        Log.with_severity log do
          job.fork
        end
      end
    end

    def erase_job_dependencies(job, rules, all_jobs, top_level_jobs)
      job.dependencies.each do |dep|
        next if top_level_jobs.include? dep.path
        next unless Orchestrator.job_rules(rules, dep)["erase"].to_s == 'true'

        dep_path = dep.path
        parents = all_jobs.select do |parent| 
          paths = parent.info[:dependencies].nil? ? parent.dependencies.collect{|d| d.path } : parent.info[:dependencies].collect{|d| Array === d ? d.last : d }
          paths.include? dep_path
        end

        next unless parents.reject{|parent| parent.done? }.empty?

        parents.each do |parent|
          Log.high "Erasing #{dep.path} from #{parent.path}"
          parent.archive_deps
          parent.copy_linked_files_dir
          parent.dependencies = parent.dependencies - [dep]
        end
        dep.clean
      end
    end

    def process(rules, jobs = nil)
      jobs, rules = rules, {} if jobs.nil?
      jobs = [jobs] if Step === jobs
      failed_jobs = []
      begin

        workload = Orchestrator.workload(jobs)
        all_jobs = workload.keys

        all_jobs.each{|job| job.clean unless (job.done? && job.updated?) || (job.error? && ! job.recoverable_error?) }

        top_level_jobs = jobs.collect{|job| job.path }
        while workload.any? 

          candidates = resources_used.keys + Orchestrator.candidates(workload, rules)
          candidates.uniq!
          raise NoWork, "No candidates and no running jobs" if candidates.empty?

          candidates.each do |job|
            case 
            when (job.error? || job.aborted?)
              begin
                if job.recoverable_error? 
                  if failed_jobs.include?(job)
                    Log.warn "Failed twice #{job.path} with recoverable error"
                    next
                  else
                    failed_jobs << job
                    job.clean
                    raise TryAgain
                  end
                else
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
              erase_job_dependencies(job, rules, all_jobs, top_level_jobs)

            when job.running?
              next

            else
              check_resources(rules, job) do
                run_with_rules(rules, job)
              end
            end
          end

          new_workload = {}
          workload.each do |k,v|
            next if k.done? || k.error? || k.aborted?
            #new_workload[k] = v.reject{|d| d.done? || ((d.error? || d.aborted?) && ! d.recoverable_error?)}
            new_workload[k] = v.reject{|d| d.done? || d.error? || d.aborted?}
          end
          workload = new_workload
          sleep timer
        end
        all_jobs.each{|s| 
          begin
            s.join
          rescue
            Log.warn "Job #{s.short_path} ended with exception #{$!.class.to_s}: #{$!.message}"
          end
        }
      rescue TryAgain
        retry
      end
    end
  end

  def self.produce_dependencies(jobs, tasks, produce_cpus = Etc.nprocessors, produce_timer = 5)
    jobs = [jobs] unless Array === jobs
    produce_list = []
    jobs.each do |job|
      next if job.done? || job.running?
      job.rec_dependencies.each do |job|
        produce_list << job if tasks.include?(job.task_name) ||
          tasks.include?(job.task_name.to_s) ||
          tasks.include?(job.full_task_name)
      end
    end

    orchestrator = Orchestrator.new produce_timer, cpus: produce_cpus.to_i
    orchestrator.process({}, produce_list)
    produce_list
  end

  def self.produce(jobs, produce_cpus: Etc.nprocessors, produce_timer: 1)
    jobs = [jobs] unless Array === jobs
    orchestrator = Orchestrator.new produce_timer.to_i, cpus: produce_cpus.to_i
    begin
      orchestrator.process({}, jobs)
    rescue Orchestrator::NoWork
    end
  end
end
