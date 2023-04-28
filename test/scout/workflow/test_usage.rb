require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/workflow'
class TestWorkflowUsage < Test::Unit::TestCase
  module UsageWorkflow
    extend Workflow
    
    self.name = "UsageWorkflow"

    self.title = "Workflow to test documentation"
    self.description = "Use this workflow to test if the documentation is correctly presented."

    desc "Desc"
    input :array, :array, "Array"
    task :step1 => :string do
    end

    dep :step1
    desc "Desc2"
    input :float, :float, "Float"
    task :step2 => :string do
    end
  end


  def test_workflow_usage
    assert_match "test if the documentation", UsageWorkflow.usage
  end

  def test_task_usage
    assert_match "Desc2", UsageWorkflow.tasks[:step2].usage
  end
end

