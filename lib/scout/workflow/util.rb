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
    Scout.workflows.glob_all("*").collect{|f| File.basename(f) }.uniq
  end

  def find_in_dependencies(name, dependencies)
    name = name.to_sym
    dependencies.select{|dep| dep.task_name.to_sym == name }
  end
end

