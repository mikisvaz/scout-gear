module Workflow
  def self.annonymous_workflow(name = nil, &block)
    mod = Module.new
    mod.extend Workflow
    mod.name = name
    mod.directory = Workflow.directory[name] if name
    mod.instance_eval(&block)
    mod
  end

  def self.installed_workflows
    Path.setup("workflows").glob_all("*").collect{|f| File.basename(f) }.uniq
  end

  def find_in_dependencies(name, dependencies)
    name = name.to_sym
    dependencies.select{|dep| dep.task_name.to_sym == name }
  end

  def all_tasks
    tasks.nil? ? [] : tasks.keys
  end

  def self.list
    Path.setup('workflows').glob('*').collect{|p| p.basename }
  end

  def task_jobs_files(task_name)
    self.directory[task_name].glob("**").
      collect{|f| %w(info files).include?(f.get_extension) ? f.unset_extension : f }.
      uniq
  end

  def task_jobs(task_name)
    task_jobs_files(task_name).collect{|f| Step.load f }
  end

  def load_job(task_name, name)
    Step.new self.directory[task_name][name]
  end
end

