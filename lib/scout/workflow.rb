require_relative 'workflow/definition'
require_relative 'workflow/util'
require_relative 'workflow/task'
require_relative 'workflow/step'
require_relative 'workflow/documentation'
require_relative 'workflow/usage'

require_relative 'resource'
require_relative 'resource/scout'

module Workflow
  class << self
    attr_accessor :workflows
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

  def self.require_workflow(workflow)
    if Open.exists?(workflow)
      workflow = workflow.find if Path === workflow
      load workflow
    end
    workflows.last
  end

  def job(name, *args)
    task = tasks[name]
    task.job(*args)
  end
end
