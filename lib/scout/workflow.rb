require_relative 'workflow/definition'
require_relative 'workflow/util'
require_relative 'workflow/task'
require_relative 'workflow/step'
require_relative 'workflow/documentation'
require_relative 'workflow/usage'
require_relative 'workflow/deployment'

require_relative 'resource'
require_relative 'resource/scout'

module Workflow
  class << self
    attr_accessor :workflows, :main
    def workflows
      @workflows ||= []
    end
  end

  attr_accessor :libdir
  def self.extended(base)
    self.workflows << base
    libdir = Path.caller_lib_dir
    return if libdir.nil?
    base.libdir = Path.setup(libdir).tap{|p| p.resource = base}
  end

  def self.require_workflow(workflow_name)
    workflow = workflow_name 
    workflow = Path.setup('workflows')[workflow_name]["workflow.rb"] unless Open.exists?(workflow)
    workflow = Path.setup('workflows')[Misc.snake_case(workflow_name)]["workflow.rb"] unless Open.exists?(workflow)
    workflow = Path.setup('workflows')[Misc.camel_case(workflow_name)]["workflow.rb"] unless Open.exists?(workflow)
    if Open.exists?(workflow)
      self.main = nil
      workflow = workflow.find if Path === workflow
      $LOAD_PATH.unshift(File.join(File.dirname(workflow), 'lib'))
      load workflow
    else
      raise "Workflow #{workflow_name} not found"
    end
    self.main || workflows.last
  end

  def job(name, *args)
    task = tasks[name]
    step = task.job(*args)
    step.extend step_module
    step
  end
end
