class Workflow::Orchestrator

  # Merge config_keys strings preserving order and de-duplicating tokens
  def self.add_config_keys(current, new_val)
    return new_val if current.nil?
    current = current * ',' if Array === current
    new_val = new_val * ',' if Array === new_val
    (new_val.to_s + ',' + current.to_s).gsub(/,\s*/, ',').split(',').reverse.uniq.reverse * ","
  end

  # Workflow-level defaults
  def self.workflow_rules(rules, workflow)
    rules = IndiferentHash.setup(rules || {})
    wf = workflow.to_s
    return {} if rules[wf].nil?
    return {} if rules[wf]["defaults"].nil?
    IndiferentHash.setup(rules[wf]["defaults"].dup)
  end

  # Prefer current unless new provides config_keys; do not override existing keys by default
  def self.merge_rules(current, new_val)
    current = IndiferentHash.setup((current || {}).dup)
    new_val = IndiferentHash.setup((new_val || {}).dup)
    return current if new_val.nil? || new_val.empty?

    new_val.each do |k, value|
      case k.to_s
      when "config_keys"
        current[k] = add_config_keys current["config_keys"], value
      when 'defaults'
        current[k] = merge_rules current[k], value
      else
        next if current.include?(k)
        current[k] = value
      end
    end
    current
  end

  # Accumulate across multiple rule sources (e.g., across jobs in a batch)
  def self.accumulate_rules(current, new_val)
    current = IndiferentHash.setup((current || {}).dup)
    new_val = IndiferentHash.setup((new_val || {}).dup)
    return current if new_val.nil? || new_val.empty?

    new_val.each do |k, value|
      case k.to_s
      when "config_keys"
        current[k] = add_config_keys current["config_keys"], value
      when "task_cpus", 'cpus'
        # choose max
        vals = [current[k], value].compact.map{|v| v.to_i }
        current[k] = vals.max unless vals.empty?
      when "time"
        # sum time budgets
        t = [current[k], value].compact.inject(0){|acc,tv| acc + Misc.timespan(tv) }
        current[k] = Misc.format_seconds(t)
      when "skip"
        skip = (current.key?(k) ? current[k] : true) && value
        if skip
          current[k] = true
        else
          current.delete k
        end
      else
        next if current.include?(k)
        current[k] = value
      end
    end
    current
  end

  # Compute task-specific rules: defaults -> workflow defaults -> task overrides
  def self.task_specific_rules(rules, workflow, task)
    rules = IndiferentHash.setup(rules || {})
    defaults = IndiferentHash.setup(rules[:defaults] || {})
    wf = workflow.to_s
    tk = task.to_s

    wf_defaults = merge_rules(workflow_rules(rules, wf), defaults)
    return IndiferentHash.setup(wf_defaults.dup) if rules[wf].nil? || rules[wf][tk].nil?

    merge_rules(rules[wf][tk], wf_defaults)
  end

  # Recursive job rules: accumulate down the dependency tree
  def self.job_rules(rules, job, force = false)
    return {} if (job.done? || job.error?) && !force
    jr = task_specific_rules(rules, job.workflow.to_s, job.task_name.to_s)
    job.dependencies.each do |dep|
      jr = accumulate_rules(jr, job_rules(rules, dep))
    end
    jr
  end

  # Build a numeric-only resources hash for scheduling (parallel orchestrator)
  def self.job_resources(rules, job)
    jr = IndiferentHash.setup(job_rules(rules, job) || {})

    resources = IndiferentHash.setup({})
    # Nested resources
    if jr[:resources].is_a?(Hash)
      jr[:resources].each do |k,v|
        resources[k] = v
      end
    end
    # Top-level aliases
    resources[:cpus] ||= jr[:cpus] if jr.key?(:cpus)
    resources[:IO]   ||= jr[:IO]   if jr.key?(:IO)
    resources[:io]   ||= jr[:io]   if jr.key?(:io)
    # Memory settings are ignored for numeric scheduling unless numeric
    resources[:mem]        ||= jr[:mem] if jr.key?(:mem)
    resources[:mem_per_cpu] ||= jr[:mem_per_cpu] if jr.key?(:mem_per_cpu)

    # Default resources fallback
    default_resources = rules["default_resources"]
    default_resources ||= rules["defaults"]["resources"] if rules["defaults"]
    default_resources ||= {}
    IndiferentHash.setup(default_resources).each do |k,v|
      resources[k] = v if resources[k].nil?
    end

    # If still empty, use cpus:1 as safe default
    resources = {:cpus => 1} if resources.empty?

    # Only keep numeric-like values for the scheduler summations/accounting
    numeric_resources = {}
    resources.each do |k,v|
      next if k.to_s == 'size'
      if Numeric === v
        numeric_resources[k] = v
      elsif v.respond_to?(:to_s) && v.to_s.strip =~ /^\d+(?:\.\d+)?$/
        numeric_resources[k] = v.to_s.include?(".") ? v.to_f : v.to_i
      end
    end

    IndiferentHash.setup(numeric_resources)
  end

  # Build resources hash directly from a rules hash (e.g., consolidated batch rules)
  def self.resources_from_rules_hash(rules_hash, global_rules = {})
    rules_hash = IndiferentHash.setup(rules_hash || {})
    resources = IndiferentHash.setup({})

    # Nested resources
    if rules_hash[:resources].is_a?(Hash)
      rules_hash[:resources].each{|k,v| resources[k] = v }
    end
    # Top-level cpus/IO
    resources[:cpus] ||= rules_hash[:cpus] if rules_hash.key?(:cpus)
    resources[:IO]   ||= rules_hash[:IO]   if rules_hash.key?(:IO)
    resources[:io]   ||= rules_hash[:io]   if rules_hash.key?(:io)
    resources[:mem]        ||= rules_hash[:mem] if rules_hash.key?(:mem)
    resources[:mem_per_cpu] ||= rules_hash[:mem_per_cpu] if rules_hash.key?(:mem_per_cpu)

    # Default resources fallback from global rules
    default_resources = global_rules["default_resources"]
    default_resources ||= global_rules["defaults"]["resources"] if global_rules["defaults"]
    default_resources ||= {}
    IndiferentHash.setup(default_resources).each do |k,v|
      resources[k] = v if resources[k].nil?
    end

    # Numeric-only for local scheduling
    numeric_resources = {}
    resources.each do |k,v|
      next if k.to_s == 'size'
      if Numeric === v
        numeric_resources[k] = v
      elsif v.respond_to?(:to_s) && v.to_s.strip =~ /^\d+(?:\.\d+)?$/
        numeric_resources[k] = v.to_s.include?(".") ? v.to_f : v.to_i
      end
    end

    IndiferentHash.setup(numeric_resources)
  end

  # Helper to extract a resources hash from various rule styles
  def self.normalize_resources_from_rules(rules_block)
    return {} if rules_block.nil? || rules_block.empty?
    rules_block = IndiferentHash.setup rules_block

    r = rules_block[:resources] || {}
    r = IndiferentHash.setup r

    r = IndiferentHash.add_defaults r,
      cpus: rules_block[:cpus] || rules_block[:task_cpus] || 1,
      time: rules_block[:time]

    r.delete_if{|k,v| v.nil?}

    IndiferentHash.setup(r)
  end

  def self.merge_rule_file(current, new)
    current = IndiferentHash.setup(current)
    new.each do |key,value|
      if current[key].nil?
        current[key] = value
      elsif Hash === value
        current[key] = merge_rules(current[key], value)
      else
        current[key] = value
      end
    end

    current
  end

  def self.load_rules(rule_files = nil)
    rule_files = [:default] if rule_files.nil?
    rule_files = [rule_files] unless Array === rule_files

    rule_files = rule_files.inject({}) do |acc,file|
      if Path.is_filename?(file) && Open.exists?(file) and Path.can_read?(file)
        file_rules = Open.yaml(file)
        raise "Unknown rule file #{file}" unless Hash === file_rules
      else
        orig = file
        file = Scout.etc.batch[file].find_with_extension(:yaml)

        if file.exists?
          file_rules = Open.yaml(file)
        else
          Log.debug "Rule file #{orig} not found"
          next acc
        end
      end

      file_rules = IndiferentHash.setup(file_rules)

      if file_rules[:import]
        imports = file_rules.delete(:import)
        merge_rule_file(file_rules, load_rules(imports))
      end

      merge_rule_file(acc, file_rules)
    end
  end

  def self.load_rules_for_job(jobs)
    jobs = [jobs] unless Array === jobs

    deploy_files = jobs.collect do |job|
      job.workflow.to_s
    end.compact

    deploy_files += jobs.collect do |job|
      job.rec_dependencies.collect{|d| d.workflow }.compact.collect(&:to_s).uniq
    end.compact.flatten

    deploy_files << :default

    load_rules(deploy_files)
  end
end
