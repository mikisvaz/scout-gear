require 'scout/entity'
require 'scout/workflow'

module EntityWorkflow

  def self.extended(base)
    base.extend Workflow
    base.extend Entity

    base.instance_variable_set(:@annotation_inputs, IndiferentHash.setup({})) unless base.instance_variables.include?(:@annotation_inputs)
    class << base
      def annotation_input(name, type=nil, desc=nil, default=nil, options = {})
        annotation name
        annotation_inputs = self.instance_variable_get("@annotation_inputs")
        annotation_inputs[name] = [type, desc, default, options]
      end
    end

    base.helper :entity do
      base.setup(clean_name.dup, inputs.to_hash)
    end

    base.helper :entity_list do 
      list = inputs.last
      list = list.load if Step === list
      base.setup(list, inputs.to_hash)
    end

    base.property job: :both  do |task_name,options={}|
      if Array === self && AnnotatedArray === self
        base.job(task_name, "Default", options.merge(list: self))
      else
        base.job(task_name, self, options)
      end
    end
  end

  def property_task(task_name, property_type=:single, *args, &block)
    task_name, result_type = task_name.keys.first, task_name.values.first if Hash === task_name

    annotation_inputs = self.instance_variable_get("@annotation_inputs")
    self.annotations.each do |annotation|
      if annotation_inputs[annotation]
        input annotation, *annotation_inputs[annotation]
      else
        input annotation
      end
    end
    case property_type
    when :single, :single2array
      input :entity, :string, "#{self.to_s} identifier", nil, jobname: true
      task(task_name => result_type, &block)
    when :both
      input :entity, :string, "#{self.to_s} identifier", nil, jobname: true
      input :list, :array, "#{self.to_s} identifier list"
      task(task_name => result_type, &block)
    else
      input :list, :array, "#{self.to_s} identifier list"
      task(task_name => result_type, &block)
    end

    property task_name => property_type do |*args|
      job = job(task_name, *args)
      Array === job ? job.collect(&:run) : job.run
    end
  end

  def entity_task(task_name, *args, &block)
    property_task(task_name, :single, *args, &block)
  end

  def list_task(task_name, *args, &block)
    property_task(task_name, :array, *args, &block)
  end

  def multiple_task(task_name, *args, &block)
    property_task(task_name, :multiple, *args, &block)
  end

  def property_task_alias(task_name, property_type=:single, *args)
    task_alias task_name, *args
    property task_name => property_type do |*args|
      job = job(task_name, *args)
      Array === job ? job.collect(&:run) : job.run
    end
  end

  def entity_task_alias(task_name, *args)
    property_task_alias(task_name, :single, *args)
  end

  def list_task_alias(task_name, *args)
    property_task_alias(task_name, :array, *args)
  end

  def multiple_task_alias(task_name, *args)
    property_task_alias(task_name, :multiple, *args)
  end
end
