require_relative 'workload'

class Workflow::Orchestrator
  def self.check_chains(chains, job)
    return [] if Symbol === job.overriden_task
    matches = []
    chains.each do |name, chain|
      workflow = job.overriden_workflow || job.workflow
      task_name = job.overriden_task || job.task_name
      next unless chain[:tasks].include?(workflow.to_s)
      next unless chain[:tasks][workflow.to_s].include?(task_name.to_s)
      matches << name
    end
    matches
  end

  def self.parse_chains(rules)
    rules = IndiferentHash.setup(rules || {})
    chains = IndiferentHash.setup({})

    # Rules may contain chains under workflows and/or top-level
    rules.each do |workflow_name, wf_rules|
      next unless wf_rules.is_a?(Hash)
      next unless wf_rules["chains"]
      wf_rules["chains"].each do |name, cr|
        cr = IndiferentHash.setup(cr.dup)
        chain_tasks = cr.delete(:tasks).to_s.split(/,\s*/)
        wf = cr.delete(:workflow) if cr.include?(:workflow)

        chain_tasks.each do |task|
          chain_workflow, chain_task = task.split('#')
          chain_task, chain_workflow = chain_workflow, wf if chain_task.nil? || chain_task.empty?

          chains[name] ||= IndiferentHash.setup({:tasks => {}, :rules => cr })
          chains[name][:tasks][chain_workflow] ||= []
          chains[name][:tasks][chain_workflow] << chain_task
        end
      end
    end

    if rules["chains"]
      rules["chains"].each do |name, cr|
        cr = IndiferentHash.setup(cr.dup)
        chain_tasks = cr.delete(:tasks).to_s.split(/,\s*/)
        wf = cr.delete(:workflow)

        chain_tasks.each do |task|
          chain_workflow, chain_task = task.split('#')
          chain_task, chain_workflow = chain_workflow, wf if chain_task.nil? || chain_task.empty?

          chains[name] ||= IndiferentHash.setup({:tasks => {}, :rules => cr })
          chains[name][:tasks][chain_workflow] ||= []
          chains[name][:tasks][chain_workflow] << chain_task
        end
      end
    end

    chains
  end

  def self.add_chain(job_chains, match, info)
    if job_chains[match]
      current = job_chains[match]
      new_info = {}
      new_info[:jobs] = (current[:jobs] + info[:jobs]).uniq
      if current[:top_level].rec_dependencies.include?(info[:top_level]) ||
          current[:top_level].input_dependencies.include?(info[:top_level])
        new_info[:top_level] = current[:top_level]
      else
        new_info[:top_level] = info[:top_level]
      end
      job_chains[match] = new_info
    else
      job_chains[match] = info
    end
  end

  def self.job_chains(rules, job, computed = {})
    chains = parse_chains(rules)
    key = Log.fingerprint([job.path, job.object_id, chains])
    return computed[key] if computed.has_key?(key)

    job_chains = check_chains(chains, job)
    job_batches = {}
    new_batches = {}
    job_dependencies(job).each do |dep|
      dep_chains = check_chains(chains, dep)
      common_chains = job_chains & dep_chains

      dep_batches = job_chains(rules, dep, computed)

      found = []
      common_chains.each do |chain|
        info = new_batches[chain]
        info = {top_level: job, jobs: [job]} if info.nil?
        if dep_batches[chain]
          found << chain
          dep_batches[chain].each do |dep_info|
            info[:jobs] += dep_info[:jobs] - info[:jobs]
          end
        else
          info[:jobs] << dep
        end
        new_batches[chain] = info
      end

      dep_batches.each do |chain,list|
        next if found.include? chain
        job_batches[chain] ||= []
        job_batches[chain].concat list
      end
    end

    new_batches.each do |match, info|
      job_batches[match] ||= []
      job_batches[match] << info
    end

    computed[key] = job_batches
  end
end
