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
          batch_dep_jobs = batch[:top_level].rec_dependencies
          target = batch[:deps].select do |target|
            batch_dep_jobs.include?(target[:top_level]) &&
              (batch[:deps] - [target] - target[:deps]).empty?
          end.first
          next if target.nil?
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
    job_chains_map = jobs.inject([]){|acc,job| acc.concat(self.job_chains(rules, job)) }

    batches = chain_batches(rules, job_chains_map, workload)
    batches = add_batch_deps(batches)
    batches = add_rules_and_consolidate(rules, batches)

    batches
  end
end
