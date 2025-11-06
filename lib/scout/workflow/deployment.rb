require_relative 'deployment/local'
require_relative 'deployment/scheduler'
require_relative 'deployment/trace'
require_relative 'deployment/queue'

module Workflow
  def self.produce(jobs)
    Workflow::LocalExecutor.produce(jobs)
  end
end
