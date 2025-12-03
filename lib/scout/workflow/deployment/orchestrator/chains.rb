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
    key = Log.fingerprint([rules, job.path, job.object_id])
    return computed[key] if computed.has_key?(key)

    chains = parse_chains(rules)
    matches = check_chains(chains, job)
    dependencies = job_dependencies(job)

    job_chains = {}
    new_job_chains = {}
    dependencies.each do |dep|
      dep_matches = check_chains(chains, dep)
      common = matches & dep_matches

      dep_chains = job_chains(rules, dep, computed)
      found = []
      dep_chains.each do |match, info|
        if common.include?(match)
          found << match
          new_info = new_job_chains[match] ||= {}
          new_info[:jobs] ||= []
          new_info[:jobs].concat info[:jobs]
          new_info[:top_level] = job
        else
          add_chain job_chains, match, info
          #job_chains << [match, info]
        end
      end

      (common - found).each do |match|
        info = {}
        info[:jobs] = [job, dep]
        info[:top_level] = job
        #job_chains << [match, info]
        add_chain job_chains, match, info
      end
    end

    new_job_chains.each do |match, info|
      info[:jobs].prepend job
      add_chain job_chains, match, info
    end

    computed[key] = job_chains
  end
end
