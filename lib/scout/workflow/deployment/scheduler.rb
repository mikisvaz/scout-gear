require_relative 'orchestrator/chains'
require_relative 'orchestrator/rules'
require_relative 'orchestrator/batches'

require_relative 'scheduler/slurm'
require_relative 'scheduler/pbs'
require_relative 'scheduler/lfs'

module Workflow::Scheduler
  def self.produce(jobs, rules = {}, options = {})
    batches = Workflow::Orchestrator.job_batches(rules, jobs)
    Workflow::Scheduler.process_batches(batches, options)
  end

  def self.process_batches(batches, process_options = {})
    failed_jobs = []

    #pending = batches.dup

    #sorted = []
    #while pending.any?
    #  leaf_nodes = batches.select{|batch| (batch[:deps] - sorted).empty? }
    #  sorted.concat(leaf_nodes - sorted)
    #  pending -= leaf_nodes
    #end

    sorted = Workflow::Orchestrator.sort_batches batches

    batch_system = Scout::Config.get :system, :batch, :scheduler, 'env:BATCH_SYSTEM', default: 'SLURM'

    batch_ids = {}
    error = []
    sorted.collect do |batch|
      job_options = batch[:rules]
      job_options = IndiferentHash.add_defaults job_options, process_options.dup

      if Workflow::Orchestrator.errors_in_batch(batch)
        Log.warn "Batch contains errors #{batch[:top_level].short_path}"
        error << batch
        next
      elsif (error_deps = error & batch[:deps]).any?
        if error_deps.reject{|b| b[:top_level].canfail? }.any?
          Log.warn "Batch depends on batches with errors #{batch[:top_level].short_path} #{Log.fingerprint(error_deps)}"
          error << batch
          next
        else
          batch[:deps] -= error_deps
        end
      end

      if batch[:deps].nil?
        batch_dependencies = [] 
      else 
        top_jobs = batch[:jobs]

        batch_dependencies = batch[:deps].collect{|dep| 
          dep_target = dep[:top_level]
          id = batch_ids[dep_target].to_s

          if dep_target.canfail?
            'canfail:' + id
          else
            id
          end
        }
      end

      job_options.merge!(:batch_dependencies => batch_dependencies )
      job_options.merge!(:manifest => batch[:jobs].collect{|d| d.task_signature })

      begin
        id, dir = case batch_system
             when 'SLURM'
               SLURM.run_job(batch[:top_level], job_options)
             when 'LSF'
               LSF.run_job(batch[:top_level], job_options)
             when 'PBS'
               PBS.run_job(batch[:top_level], job_options)
             when nil
               raise "No batch system specified"
             else
               raise "Unknown batch system #{batch_system}"
             end
        batch_ids[batch[:top_level]] = id
      rescue DryRun
        $!.message
      end
    end
  end
end
