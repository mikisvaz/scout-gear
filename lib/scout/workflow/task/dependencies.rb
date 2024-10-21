module Task
  def dependencies(id, provided_inputs, non_default_inputs = [], compute = {})
    return [] if deps.nil?
    dependencies = []
    
    provided_inputs ||= {}

    # Helper function
    load_dep = proc do |id, workflow, task, step_options, definition_options, dependencies|
      task = step_options.delete(:task) if step_options.include?(:task)
      workflow = step_options.delete(:workflow) if step_options.include?(:workflow)
      id = step_options.delete(:id) if step_options.include?(:id)
      id = step_options.delete(:jobname) if step_options.include?(:jobname)
      id = nil if id == Task::DEFAULT_NAME

      step_inputs = step_options.include?(:inputs)? step_options.delete(:inputs) : step_options
      step_inputs = IndiferentHash.add_defaults step_inputs.dup, definition_options


      resolved_inputs = {}
      step_inputs.each do |k,v|
        if Symbol === v
          input_dep = dependencies.select{|d| d.task_name == v }.first
          resolved_inputs[k] = input_dep || provided_inputs[v] || step_inputs[v] || v
        else
          resolved_inputs[k] = v
        end
      end

      job = workflow.job(task, id, resolved_inputs)
      compute_options = definition_options[:compute] || []
      compute_options = [compute_options] unless Array === compute_options
      compute_options << :canfail if definition_options[:canfail]
      compute_options << :produce if definition_options[:produce]
      compute_options << :stream if definition_options[:stream]
      compute[job.path] = compute_options if compute_options.any?

      job.overriden = false if definition_options[:not_overriden]

      [job, step_inputs]
    end

    # Helper function
    find_dep_non_default_inputs = proc do |dep,definition_options,step_inputs={}|
      dep_non_default_inputs = dep.non_default_inputs
      dep_non_default_inputs.select do |name|
        step_inputs.include?(name)  
      end
      dep_non_default_inputs.reject! do |name|
        definition_options.include?(name)
      end

      dep_non_default_inputs
    end

    deps.each do |workflow,task,definition_options,block=nil|
      definition_options = definition_options.dup
      definition_options[:id] = definition_options.delete(:jobname) if definition_options.include?(:jobname)

      if provided_inputs.include?(overriden = [workflow.name, task] * "#")
        dep = provided_inputs[overriden]
        dep = Step.new dep unless Step === dep
        dep = dep.dup
        dep.type = workflow.tasks[task].type
        dep.overriden_task = task
        dep.overriden_workflow = workflow
        dependencies << dep
        non_default_inputs << overriden
        next
      end

      definition_options ||= {}

      if block
        fixed_provided_inputs = self.assign_inputs(provided_inputs).first.to_hash
        self.inputs.each do |name,type,desc,value|
          fixed_provided_inputs[name] = value unless fixed_provided_inputs.include?(name)
        end
        fixed_provided_inputs = IndiferentHash.add_defaults fixed_provided_inputs, provided_inputs
        block_options = IndiferentHash.add_defaults definition_options.dup, fixed_provided_inputs

        res = block.call id, block_options, dependencies

        case res
        when Step
          dep = res
          dependencies << dep
          dep_non_default_inputs = find_dep_non_default_inputs.call(dep, definition_options)
          non_default_inputs.concat(dep_non_default_inputs)
        when Hash
          step_options = block_options.merge(res)
          dep, step_inputs = load_dep.call(id, workflow, task, step_options.dup, block_options, dependencies)
          dependencies << dep
          dep_non_default_inputs = find_dep_non_default_inputs.call(dep, definition_options, step_inputs)
          non_default_inputs.concat(dep_non_default_inputs)
        when Array
          res.each do |_res|
            if Hash === _res
              step_options = block_options.merge(_res)
              dep, step_inputs = load_dep.call(id, workflow, task, step_options.dup, block_options, dependencies)
              dependencies << dep
              dep_non_default_inputs = find_dep_non_default_inputs.call(dep, definition_options, step_inputs)
              non_default_inputs.concat(dep_non_default_inputs)
            else
              dep = _res
              dependencies << dep
              dep_non_default_inputs = find_dep_non_default_inputs.call(dep, definition_options)
              non_default_inputs.concat(dep_non_default_inputs)
            end
          end
        end
      else
        step_options = IndiferentHash.add_defaults definition_options.dup, provided_inputs
        dep, step_inputs = load_dep.call(id, workflow, task, step_options.dup, definition_options, dependencies)
        dependencies << dep
        dep_non_default_inputs = find_dep_non_default_inputs.call(dep, definition_options, step_inputs)
        non_default_inputs.concat(dep_non_default_inputs)
      end
    end

    dependencies
  end
end
