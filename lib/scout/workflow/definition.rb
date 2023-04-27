require_relative '../meta_extension'

module Workflow
  extend MetaExtension
  extension_attr :name, :tasks

  class << self
    attr_accessor :directory

    def directory
      @directory ||= Path.setup('var/jobs')
    end

  end

  def name
    @name ||= self.to_s
  end

  attr_accessor :directory
  def directory
    @directory ||= Workflow.directory[name]
  end

  def directory=(directory)
    @directory = directory
    @tasks.each{|name,d| d.directory = directory[name] } if @tasks
  end

  def annotate_next_task(type, obj)
    @annotate_next_task ||= {}
    @annotate_next_task[type] ||= []
    @annotate_next_task[type] << obj
  end

  def dep(*args, &block)
    case args.length
    when 3
      workflow, task, options = args
    when 2
      if Hash === args.last
        task, options = args
      else
        workflow, task = args
      end
    when 1
      task = args.first
    end
    workflow = self if workflow.nil?
    options = {} if options.nil?
    annotate_next_task :deps, [workflow, task, options, block, args]
  end

  def input(*args)
    annotate_next_task(:inputs, args)
  end

  def task(name_and_type, &block)
    name, type = name_and_type.collect.first
    @tasks ||= IndiferentHash.setup({})
    begin
      @annotate_next_task ||= {}
      @tasks[name] = Task.setup(block, @annotate_next_task.merge(name: name, type: type, directory: directory[name]))
    ensure
      @annotate_next_task = {}
    end
  end

  def desc(description)
    annotate_next_task(:desc, description)
  end
end
