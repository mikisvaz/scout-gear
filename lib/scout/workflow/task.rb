require 'scout/annotation'
require 'scout/named_array'
require_relative 'step'
require_relative 'task/inputs'
require_relative 'task/dependencies'

module Task
  extend Annotation
  annotation :name, :type, :inputs, :deps, :directory, :description, :returns, :extension, :workflow

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

  def directory
    @directory ||= Task.default_directory
  end

  def exec_on(binding = self, *inputs)
    binding.instance_exec(*inputs, &self)
  end

  def job(id = nil, provided_inputs = nil)

    if Hash === provided_inputs
      memory_inputs = provided_inputs.values_at *self.recursive_inputs.collect{|t| t.first }.uniq
      memory_inputs += provided_inputs.select{|k,v| k.to_s.include?("#") }.collect{|p| p * "=" }
      memory_inputs << provided_inputs[:load_inputs]
    else
      memory_inputs = provided_inputs
    end

    Persist.memory("Task job #{self.name} #{id}", other_options: {task: self, id: id, provided_inputs: memory_inputs}) do 
      provided_inputs, id = id, nil if (provided_inputs.nil? || provided_inputs.empty?) && (Hash === id || Array === id)
      provided_inputs = {} if provided_inputs.nil?
      IndiferentHash.setup(provided_inputs)

      jobname_input = nil
      inputs.each do |name,type,desc,default,input_options|
        next unless input_options && input_options[:jobname]
        jobname_input = name
      end

      id = provided_inputs[jobname_input] if jobname_input && id.nil?
      #id = provided_inputs[:id] if provided_inputs.include?(:id)

      missing_inputs = []
      self.inputs.each do |input,type,desc,val,options|
        next unless options && options[:required]
        missing_inputs << input unless provided_inputs.include?(input)
      end if self.inputs

      if missing_inputs.length == 1
        raise ParameterException, "Input '#{missing_inputs.first}' is required but was not provided or is nil"
      end

      if missing_inputs.length > 1
        raise ParameterException, "Inputs #{Misc.humanize_list(missing_inputs)} are required but were not provided or are nil"
      end

      provided_inputs = load_inputs(provided_inputs.delete(:load_inputs)).merge(provided_inputs) if Hash === provided_inputs && provided_inputs[:load_inputs]

      job_inputs, non_default_inputs, input_digest_str = process_inputs provided_inputs, id

      compute = {}
      dependencies = dependencies(id, provided_inputs, non_default_inputs, compute)

      #non_default_inputs.concat provided_inputs.keys.select{|k| String === k && k.include?("#") } if Hash === provided_inputs

      non_default_inputs.uniq!

      id = DEFAULT_NAME if id.nil?

      if non_default_inputs.any? && !(non_default_inputs == [jobname_input] && provided_inputs[jobname_input] == id)
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

      if hash
        Log.debug "ID #{self.name} #{id} - #{hash}: #{Log.fingerprint(:input_digest => input_digest_str, :non_default_inputs => non_default_inputs, :dependencies => dependencies)}"
      else
        Log.debug "ID #{self.name} #{id} - Clean"
      end
      NamedArray.setup(job_inputs, @inputs.collect{|i| i[0] }) if @inputs
      step_provided_inputs = Hash === provided_inputs ? provided_inputs.slice(*non_default_inputs) : provided_inputs
      Step.new path.find, job_inputs, dependencies, id, non_default_inputs, step_provided_inputs, compute, &self
    end
  end

  def alias?
    @extension == :dep_task
  end
end
