require_relative '../meta_extension'

module Workflow
  extend MetaExtension
  extension_attr :name, :tasks, :helpers

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
    @tasks.each{|name,d| d.directory = directory[name] } if @tasks
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
    end
    workflow = self if workflow.nil?
    options = {} if options.nil?
    annotate_next_task :deps, [workflow, task, options, block, args]
  end

  def input(*args)
    annotate_next_task(:inputs, args)
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
    name, type = name_and_type.collect.first
    @tasks ||= IndiferentHash.setup({})
    begin
      @annotate_next_task ||= {}
      task = Task.setup(block, @annotate_next_task.merge(name: name, type: type, directory: directory[name]))
      @tasks[name] = task
    ensure
      @annotate_next_task = {}
    end
  end

  def task_alias(name, workflow, oname, *rest, &block)
    dep(workflow, oname, *rest, &block) 
    extension :dep_task unless @extension
    returns workflow.tasks[oname].returns if workflow.tasks.include?(oname) unless @returns 
    task name => nil do
      raise RbbtException, "dep_task does not have any dependencies" if dependencies.empty?
      Step.wait_for_jobs dependencies.select{|d| d.streaming? }
      dep = dependencies.last
      dep.join
      raise dep.get_exception if dep.error?
      raise Aborted, "Aborted dependency #{dep.path}" if dep.aborted?
      set_info :result_type, dep.info[:result_type]
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
end
