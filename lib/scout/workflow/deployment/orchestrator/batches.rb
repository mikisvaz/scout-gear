require_relative 'rules'
require_relative 'workload'
require_relative 'chains'

class Workflow::Orchestrator

  def self.chain_batches(rules, chains, workload)
    chain_rules = parse_chains(rules)

    batches = []
    jobs = workload.keys
    while job = jobs.pop
      next if job.done?
      matches = chains.select{|name,info| info[:jobs].include? job }
      if matches.any?
        name, info = matches.sort_by do |n, info|
          num_jobs = info[:jobs].length
          total_tasks = chain_rules[n][:tasks].values.flatten.uniq.length
          num_jobs.to_f + 1.0/total_tasks
        end.last
        jobs = jobs - info[:jobs]
        info[:chain] = name
        batch = info
      else
        batch = {:jobs => [job], :top_level => job}
      end

      chains.delete_if{|n,info| batch[:jobs].include? info[:top_level] }

      chains.each do |n,info|
        info[:jobs] = info[:jobs] - batch[:jobs]
      end

      chains.delete_if{|n,info| info[:jobs].length < 2 }

      batches << IndiferentHash.setup(batch)
    end

    batches
  end

  def self.add_batch_deps(batches)
    batches.each do |batch|
      jobs = batch[:jobs]
      all_deps = jobs.collect{|j| job_dependencies(j) }.flatten.uniq - jobs

      minimum = all_deps.dup
      all_deps.each do |dep|
        minimum -= job_dependencies(dep)
      end

      all_deps = minimum
      deps = all_deps.collect do |d|
        (batches - [batch]).select{|b| b[:jobs].collect(&:path).include? d.path }
      end.flatten.uniq
      batch[:deps] = deps
    end

    batches
  end

  def self.add_rules_and_consolidate(rules, batches)
    chain_rules = parse_chains(rules)

    batches.each do |batch|
      job_rules_acc = batch[:jobs].inject(nil) do |acc, p|
        job, deps = p
        workflow = job.workflow
        task_name = job.task_name
        task_rules = task_specific_rules(rules, workflow, task_name)
        acc = accumulate_rules(acc, task_rules.dup)
        acc
      end

      if chain = batch[:chain]
        batch[:rules] = merge_rules(chain_rules[chain][:rules].dup, job_rules_acc)
      else
        batch[:rules] = job_rules_acc
      end
    end

    begin
      batches.each do |batch|
        batch[:deps] = batch[:deps].collect do |dep|
          dep[:target] || dep
        end if batch[:deps]
      end

      batches.each do |batch|
        next if batch[:top_level].overriden?
        next unless batch[:rules] && batch[:rules][:skip]
        batch[:rules].delete :skip
        next if batch[:deps].nil?

        if batch[:deps].any?
          batch_dep_jobs = batch[:top_level].rec_dependencies.to_a
          target = batch[:deps].select do |target|
            target_deps = []
            stack = [target]
            while stack.any?
              c = stack.pop
              target_deps << c
              stack.concat c[:deps]
            end
            (batch[:deps] - target_deps).empty?
          end.first
          next if target.nil?
          all_target_jobs = ([target] + target[:deps]).collect{|d| d[:jobs] }.flatten
          next if all_target_jobs.reject{|j| batch_dep_jobs.include? j }.any?
          target[:jobs] = batch[:jobs] + target[:jobs]
          target[:deps] = (target[:deps] + batch[:deps]).uniq - [target]
          target[:top_level] = batch[:top_level]
          target[:rules] = accumulate_rules(target[:rules], batch[:rules])
          batch[:target] = target
        end
        raise TryAgain
      end
    rescue TryAgain
      retry
    end

    batches.delete_if{|b| b[:target] }

    batches
  end

  def self.job_batches(rules, jobs)
    jobs = [jobs] unless Array === jobs

    workload = job_workload(jobs)
    job_chain_list = []

    jobs.each do |job|
      job_chains = self.job_chains(rules, job)
      job_chains.each do |chain,list|
        list.each do |info|
          job_chain_list << [chain,info]
        end
      end
    end

    batches = chain_batches(rules, job_chain_list, workload)
    batches = add_batch_deps(batches)
    batches = add_rules_and_consolidate(rules, batches)

    batches
  end

  def self.sort_batches(batches)
    pending = batches.dup
    sorted = []
    while pending.any?
      leaf_nodes = batches.select{|batch| batch[:deps].nil? || (batch[:deps] - sorted).empty? }
      sorted.concat(leaf_nodes - sorted)
      pending -= leaf_nodes
    end
    sorted
  end

  def self.errors_in_batch(batch)
    errors = batch[:jobs].select do |job|
      job.error? && ! job.recoverable_error?
    end

    errors.empty? ? false : errors
  end

  def self.clean_batches(batches)
    error = []
    batches.collect do |batch|
      if failed = Workflow::Orchestrator.errors_in_batch(batch)
        Log.warn "Batch contains errors #{batch[:top_level].short_path} #{Log.fingerprint failed}"
        error << batch
        next
      elsif (error_deps = error & batch[:deps]).any?
        if error_deps.reject{|b| b[:top_level].canfail? }.any?
          Log.warn "Batch depends on batches with errors #{batch[:top_level].short_path} #{Log.fingerprint(error_deps.collect{|d| d[:top_level] })}"
          error << batch
          next
        else
          batch[:deps] -= error_deps
        end
      end
      batch
    end.compact
  end

  def self.inspect_batch(batch)
    batch.merge(deps: batch[:deps].collect{|b| b[:top_level] })
  end
end
