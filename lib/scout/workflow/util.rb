module Workflow
  def self.annonymous_workflow(name = nil, &block)
    mod = class << Module.new
      extend Workflow
      self
    end
    mod.name = name
    mod.directory = Workflow.directory[name] if name
    mod.instance_eval &block
    mod
  end
end

