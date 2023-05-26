require_relative '../meta_extension'
require_relative '../named_array'
require_relative 'step'
require_relative 'task/inputs'
require_relative 'task/dependencies'

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

  def job(id = DEFAULT_NAME, provided_inputs = nil )
    provided_inputs, id = id, DEFAULT_NAME if (provided_inputs.nil? || provided_inputs.empty?) && (Hash === id || Array === id)
    provided_inputs = {} if provided_inputs.nil?
    id = DEFAULT_NAME if id.nil?

    inputs, non_default_inputs, input_digest_str = process_inputs provided_inputs

    compute = {}
    dependencies = dependencies(id, provided_inputs, non_default_inputs, compute)

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
      Step.new path.find, inputs, dependencies, id, non_default_inputs, compute, &self
    end
  end
end
