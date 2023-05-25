require_relative '../meta_extension'
require_relative '../named_array'
require_relative 'step'
require_relative 'task/inputs'

module Task
  extend MetaExtension
  extension_attr :name, :type, :inputs, :deps, :directory, :description, :returns, :extension, :workflow

  DEFAULT_NAME = "Default"

  class << self
    attr_accessor :default_directory

    def default_directory
      @default_directory ||= Path.setup('var/jobs/Task')
    end
  end

  def inputs
    @inputs ||= []
  end

  def recursive_inputs
    return inputs if deps.nil?
    deps.inject(inputs) do |acc,dep|
      workflow, task = dep
      next acc if workflow.nil? || task.nil?
      acc += workflow.tasks[task].recursive_inputs
    end
  end

  def directory
    @directory ||= Task.default_directory
  end

  def exec_on(binding = self, *inputs)
    binding.instance_exec(*inputs, &self)
  end

  def dependencies(id, provided_inputs, non_default_inputs = [])
    return [] if deps.nil?
    dependencies = []
    
    provided_inputs ||= {}

    # Helper function
    load_dep = proc do |id, workflow, task, step_options, definition_options, dependencies|
      task = step_options.delete(:task) if step_options.include?(:task)
      workflow = step_options.delete(:workflow) if step_options.include?(:workflow)
      id = step_options.delete(:id) if step_options.include?(:id)
      id = step_options.delete(:jobname) if step_options.include?(:jobname)

      step_inputs = step_options.include?(:inputs)? step_options.delete(:inputs) : step_options
      step_inputs = IndiferentHash.add_defaults step_inputs, definition_options

      resolved_inputs = {}
      step_inputs.each do |k,v|
        if Symbol === v
          input_dep = dependencies.select{|d| d.task_name == v }.first
          resolved_inputs[k] = input_dep || step_inputs[v] || k
        else
          resolved_inputs[k] = v
        end
      end
      [workflow.job(task, id, resolved_inputs), step_inputs]
    end

    # Helper function
    find_dep_non_default_inputs = proc do |dep,definition_options,step_inputs={}|
      dep_non_default_inputs = dep.non_default_inputs
      dep_non_default_inputs.select do |name|
        step_inputs.include?(name)  
      end
      dep_non_default_inputs.reject! do |name|
        definition_options.include?(name) && 
          (definition_options[name] != :placeholder || definition_options[name] != dep.inputs[name])
      end

      dep_non_default_inputs
    end

    deps.each do |workflow,task,definition_options,block=nil|
      definition_options[:id] = definition_options.delete(:jobname) if definition_options.include?(:jobname)

      if provided_inputs.include?(overriden = [workflow.name, task] * "#")
        dep = provided_inputs[overriden]
        dep = Step.new dep unless Step === dep
        dep.type = workflow.tasks[task].type
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
          dep_non_default_inputs = find_dep_non_default_inputs.call(dep, block_options)
          non_default_inputs.concat(dep_non_default_inputs)
        when Hash
          step_options = block_options.merge(res)
          dep, step_inputs = load_dep.call(id, workflow, task, step_options, block_options, dependencies)
          dependencies << dep
          dep_non_default_inputs = find_dep_non_default_inputs.call(dep, definition_options, step_inputs)
          non_default_inputs.concat(dep_non_default_inputs)
        when Array
          res.each do |_res|
            if Hash === _res
              step_options = block_options.merge(_res)
              dep, step_inputs = load_dep.call(id, workflow, task, step_options, block_options, dependencies)
              dependencies << dep
              dep_non_default_inputs = find_dep_non_default_inputs.call(dep, definition_options, step_inputs)
              non_default_inputs.concat(dep_non_default_inputs)
            else
              dep = _res
              dependencies << dep
              dep_non_default_inputs = find_dep_non_default_inputs.call(dep, block_options)
              non_default_inputs.concat(dep_non_default_inputs)
            end
          end
        end
      else
        step_options = IndiferentHash.add_defaults definition_options.dup, provided_inputs
        dep, step_inputs = load_dep.call(id, workflow, task, step_options, definition_options, dependencies)
        dependencies << dep
        dep_non_default_inputs = find_dep_non_default_inputs.call(dep, definition_options, step_inputs)
        non_default_inputs.concat(dep_non_default_inputs)
      end
    end

    dependencies
  end

  def job(id = DEFAULT_NAME, provided_inputs = nil )
    provided_inputs, id = id, DEFAULT_NAME if (provided_inputs.nil? || provided_inputs.empty?) && (Hash === id || Array === id)
    provided_inputs = {} if provided_inputs.nil?
    id = DEFAULT_NAME if id.nil?

    inputs, non_default_inputs, input_digest_str = process_inputs provided_inputs

    dependencies = dependencies(id, provided_inputs, non_default_inputs)

    non_default_inputs.concat provided_inputs.keys.select{|k| String === k && k.include?("#") } if Hash === provided_inputs

    non_default_inputs.uniq!

    if non_default_inputs.any?
      hash = Misc.digest(:inputs => input_digest_str, :dependencies => dependencies)
      name = [id, hash] * "_"
    else
      name = id
    end

    extension = self.extension
    if extension == :dep_task
      extension = nil
      if dependencies.any?
        dep_basename = File.basename(dependencies.last.path)
        if dep_basename.include? "."
          parts = dep_basename.split(".")
          extension = [parts.pop]
          while parts.last.length <= 4
            extension << parts.pop
          end
          extension = extension.reverse * "."
        end
      end
    end

    path = directory[name]

    path = path.set_extension(extension) if extension

    Persist.memory(path) do 
      if hash
        Log.debug "ID #{self.name} #{id} - #{hash}: #{Log.fingerprint(:input_digest => input_digest_str, :non_default_inputs => non_default_inputs, :dependencies => dependencies)}"
      else
        Log.debug "ID #{self.name} #{id} - Clean"
      end
      NamedArray.setup(inputs, @inputs.collect{|i| i[0] }) if @inputs
      Step.new path.find, inputs, dependencies, id, non_default_inputs, &self
    end
  end
end
