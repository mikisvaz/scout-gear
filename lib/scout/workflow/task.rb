require_relative '../meta_extension'
require_relative 'step'
require_relative 'task/inputs'

module Task
  extend MetaExtension
  extension_attr :name, :type, :inputs, :deps, :directory, :description

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
      next if workflow.nil?
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

    load_dep = proc do |id, workflow, task, inputs, hash_options, dependencies|
      task = hash_options[:task] if hash_options.include?(:task)
      workflow = hash_options[:workflow] if hash_options.include?(:workflow)
      id = hash_options[:id] if hash_options.include? :id

      hash_inputs = hash_options.include?(:inputs)? hash_options[:inputs] : hash_options
      inputs = IndiferentHash.add_defaults hash_inputs, inputs

      resolved_inputs = {}
      inputs.each do |k,v|
        if Symbol === v
          input_dep = dependencies.select{|d| d.task_name == v}.first
          resolved_inputs[k] = input_dep || inputs[v] || k
        else
          resolved_inputs[k] = v
        end
      end
      workflow.job(task, id, resolved_inputs)
    end

    deps.each do |workflow,task,options,block=nil|
      if provided_inputs.include?(overriden = [workflow.name, task] * "#")
        dep = provided_inputs[overriden]
        dep = Step.new dep unless Step === dep
        dep.type = workflow.tasks[task].type
        dependencies << dep
        non_default_inputs << overriden
        next
      end

      options ||= {}
      if block
        inputs = IndiferentHash.add_defaults options.dup, provided_inputs

        res = block.call id, inputs, dependencies

        case res
        when Step
          dep = res
          dependencies << dep
          dep_non_default_inputs = dep.task.assign_inputs(dep.inputs).last
          non_default_inputs.concat(dep_non_default_inputs - options.keys)
        when Hash
          new_options = res
          dep = load_dep.call(id, workflow, task, inputs, new_options, dependencies)
          dependencies << dep
          dep_non_default_inputs = dep.task.assign_inputs(dep.inputs).last
          dep_non_default_inputs -= options.keys 
          if new_options.include?(:inputs)
            dep_non_default_inputs -= new_options[:inputs].keys 
          else
            dep_non_default_inputs -= new_options.keys
          end
          non_default_inputs.concat(dep_non_default_inputs)
        when Array
          res.each do |_res|
            if Hash === _res
              new_options = _res
              dep = load_dep.call(id, workflow, task, inputs, new_options, dependencies)
              dependencies << dep
              dep_non_default_inputs = dep.task.assign_inputs(dep.inputs).last
              dep_non_default_inputs -= options.keys 
              if new_options.include?(:inputs)
                dep_non_default_inputs -= new_options[:inputs].keys 
              else
                dep_non_default_inputs -= new_options.keys
              end
              non_default_inputs.concat(dep_non_default_inputs)
            else
              dep = _res
              dependencies << dep
              dep_non_default_inputs = dep.task.assign_inputs(dep.inputs).last
              non_default_inputs.concat(dep_non_default_inputs - options.keys)
            end
          end
        end
      else
        inputs = IndiferentHash.add_defaults options.dup, provided_inputs
        dep = load_dep.call(id, workflow, task, inputs, {}, dependencies)
        dependencies << dep
        dep_non_default_inputs = dep.task.assign_inputs(dep.inputs).last
        non_default_inputs.concat(dep_non_default_inputs - options.keys)
      end
    end

    dependencies
  end

  def job(id = DEFAULT_NAME, provided_inputs = nil )
    provided_inputs, id = id, DEFAULT_NAME if (provided_inputs.nil? || provided_inputs.empty?) && (Hash === id || Array === id)
    provided_inputs = {} if provided_inputs.nil?
    id = DEFAULT_NAME if id.nil?

    inputs, non_default_inputs, input_hash = process_inputs provided_inputs

    dependencies = dependencies(id, provided_inputs, non_default_inputs)

    non_default_inputs.concat provided_inputs.keys.select{|k| String === k && k.include?("#") } if Hash === provided_inputs

    if non_default_inputs.any?
      hash = Misc.digest(:inputs => input_hash, :non_default_inputs => non_default_inputs, :dependencies => dependencies)
      Log.debug "Hash #{name} - #{hash}: #{Misc.digest_str(:inputs => inputs, :dependencies => dependencies)}"
      id = [id, hash] * "_"
    end

    path = directory[id]

    Step.new path.find, inputs, dependencies, &self
  end
end
