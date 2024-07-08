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

  def helper(name, *args, **kwargs, &block)
    if block_given?
      helpers[name] = block
    else
      raise RbbtException, "helper #{name} unkown in #{self} workflow" unless helpers[name]
      o = Object.new
      o.extend step_module
      o.send(name, *args, **kwargs)
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

  def extension(extension)
    annotate_next_task_single(:extension, extension)
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
      @annotate_next_task[:extension] ||=  
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

  FORGET_TASK_ALIAS = begin 
                        %w(SCOUT_FORGET_TASK_ALIAS SCOUT_FORGET_DEP_TASKS RBBT_FORGET_DEP_TASKS).select do |var|
                          ENV[var] == 'true'
                        end.any?
                      end
  REMOVE_TASK_ALIAS = begin 
                        remove = %w(SCOUT_REMOVE_TASK_ALIAS SCOUT_REMOVE_DEP_TASKS RBBT_REMOVE_DEP_TASKS).select do |var|
                          ENV.include?(var) && ENV[var] != 'false'
                        end.first
                        remove.nil? ? false : remove
                      end
  def task_alias(name, workflow, oname, *rest, &block)
    dep(workflow, oname, *rest, &block) 
    extension :dep_task unless @extension
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
      raise dep.exception if dep.error?
      raise Aborted, "Aborted dependency #{dep.path}" if dep.aborted?
      set_info :type, dep.info[:type]

      forget = config :forget_task_alias, "forget_task_alias"
      forget = config :forget_dep_tasks, "forget_dep_tasks", :default => FORGET_TASK_ALIAS if forget.nil?

      if forget
        remove = config :remove_task_alias, "remove_task_alias"
        remove = config :remove_dep_tasks, "remove_dep_tasks", :default => REMOVE_TASK_ALIAS if remove.nil?

        Log.medium "Forget task_alias (remove: #{remove}): #{short_path}"

        self.archive_deps
        self.copy_linked_files_dir
        self.dependencies = self.dependencies - [dep]
        Open.rm_rf self.files_dir if Open.exist? self.files_dir
        FileUtils.cp_r dep.files_dir, self.files_dir if Open.exist?(dep.files_dir)

        if dep.overriden? 
          Open.link dep.path, self.tmp_path
        else
          Open.ln_h dep.path, self.tmp_path

          case remove.to_s
          when 'true'
            dep.clean
          when 'recursive'
            (dep.dependencies + dep.rec_dependencies).uniq.each do |d|
              next if d.overriden
              d.clean unless Scout::Config.get(:remove_dep, "task:#{d.task_signature}", "task:#{d.task_name}", "workflow:#{d.workflow.name}", :default => true).to_s == 'false'
            end
            dep.clean unless Scout::Config.get(:remove_dep, "task:#{dep.task_signature}", "task:#{dep.task_name}", "workflow:#{dep.workflow.name}", :default => true).to_s == 'false'
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
