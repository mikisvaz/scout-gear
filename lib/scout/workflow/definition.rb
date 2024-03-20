require 'scout/annotation'

module Workflow
  extend Annotation
  annotation :name, :tasks, :helpers

  class << self
    attr_accessor :directory

    def directory
      @directory ||= Path.setup('var/jobs')
    end

  end

  def name
    @name ||= self.to_s
  end

  def helpers
    @helpers ||= {}
  end

  def helper(name, *args, &block)
    if block_given?
      helpers[name] = block
    else
      raise RbbtException, "helper #{name} unkown in #{self} workflow" unless helpers[name]
      helpers[name].call(*args)
    end
  end

  def step_module
    @_m ||= begin
              m = Module.new

              helpers.each do |name,block|
                m.send(:define_method, name, &block)
              end

              m
            end
    @_m
  end

  attr_accessor :directory
  def directory
    @directory ||= Workflow.directory[name]
  end

  def directory=(directory)
    @directory = directory
    @tasks.each{|name,d| d.directory = Path === directory ? directory[name] : File.join(directory, name.to_s) } if @tasks
  end

  def annotate_next_task(type, obj)
    @annotate_next_task ||= {}
    @annotate_next_task[type] ||= []
    @annotate_next_task[type] << obj
  end

  def annotate_next_task_single(type, obj)
    @annotate_next_task ||= {}
    @annotate_next_task[type] = obj
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
      options, task = task, nil if Hash === task
    end
    workflow = self if workflow.nil?
    options = {} if options.nil?
    task = task.to_sym if task
    annotate_next_task :deps, [workflow, task, options, block, args]
  end

  def input(name, type = nil, *rest)
    name = name.to_sym
    type = type.to_sym if type
    annotate_next_task(:inputs, [name, type] + rest)
  end

  def desc(description)
    annotate_next_task_single(:description, description)
  end

  def returns(type)
    annotate_next_task_single(:returns, type)
  end

  def annotation(annotation)
    annotate_next_task_single(:annotation, annotation)
  end

  def task(name_and_type, &block)
    case name_and_type
    when Hash
      name, type = name_and_type.collect.first
    when Symbol
      name, type = [name_and_type, :binary]
    when String
      name, type = [name_and_type, :binary]
    end
    type = type.to_sym if String === type
    name = name.to_sym if String === name
    @tasks ||= IndiferentHash.setup({})
    block = lambda &self.method(name) if block.nil?
    begin
      @annotate_next_task ||= {}
      @annotate_next_task[:annotation] ||=  
        case type
        when :tsv
          "tsv"
        when :yaml
          "yaml"
        when :marshal
          "marshal"
        when :json
          "json"
        else
          nil
        end

      task = Task.setup(block, @annotate_next_task.merge(name: name, type: type, directory: directory[name], workflow: self))
      @tasks[name] = task
    ensure
      @annotate_next_task = {}
    end
  end

  FORGET_DEP_TASKS = ENV["SCOUT_FORGET_DEP_TASKS"] == "true"
  REMOVE_DEP_TASKS = ENV["SCOUT_REMOVE_DEP_TASKS"] == "true"
  def task_alias(name, workflow, oname, *rest, &block)
    dep(workflow, oname, *rest, &block) 
    annotation :dep_task unless @annotation
    task_proc = workflow.tasks[oname] if workflow.tasks
    if task_proc
      returns task_proc.returns if @returns.nil?
      type = task_proc.type 
    end
    task name => type do
      raise RbbtException, "dep_task does not have any dependencies" if dependencies.empty?
      Step.wait_for_jobs dependencies.select{|d| d.streaming? }
      dep = dependencies.last
      dep.join
      raise dep.get_exception if dep.error?
      raise Aborted, "Aborted dependency #{dep.path}" if dep.aborted?
      set_info :type, dep.info[:type]
      forget = config :forget_dep_tasks, "forget_dep_tasks", :default => FORGET_DEP_TASKS
      if forget
        remove = config :remove_dep_tasks, "remove_dep_tasks", :default => REMOVE_DEP_TASKS

        self.archive_deps
        self.copy_files_dir
        self.dependencies = self.dependencies - [dep]
        Open.rm_rf self.files_dir if Open.exist? self.files_dir
        FileUtils.cp_r dep.files_dir, self.files_dir if Open.exist?(dep.files_dir)

        if dep.overriden || ! Workflow.job_path?(dep.path)
          Open.link dep.path, self.tmp_path
        else
          Open.ln_h dep.path, self.tmp_path

          case remove.to_s
          when 'true'
            dep.clean
          when 'recursive'
            (dep.dependencies + dep.rec_dependencies).uniq.each do |d|
              next if d.overriden
              d.clean unless config(:remove_dep, d.task_signature, d.task_name, d.workflow.to_s, :default => true).to_s == 'false'
            end
            dep.clean unless config(:remove_dep, dep.task_signature, dep.task_name, dep.workflow.to_s, :default => true).to_s == 'false'
          end 
        end
      else
        if Open.exists?(dep.files_dir)
          Open.rm_rf self.files_dir 
          Open.link dep.files_dir, self.files_dir
        end
        if defined?(RemoteStep) && RemoteStep === dep
          Open.write(self.tmp_path, Open.read(dep.path))
        else
          Open.link dep.path, self.path
        end
      end
      nil
    end
  end

  alias dep_task task_alias

  def export(*args)
  end

  alias export_synchronous export
  alias export_asynchronous export
  alias export_exec export
  alias export_stream export
end
