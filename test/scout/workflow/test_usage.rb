require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/workflow'
class TestWorkflowUsage < Test::Unit::TestCase
  module UsageWorkflow
    extend Workflow
    
    self.name = "UsageWorkflow"

    self.title = "Workflow to test documentation"
    self.description = "Use this workflow to evaluate if the documentation is correctly presented."

    desc "Desc"
    input :array, :array, "Array"
    task :step1 => :string do |a|
      a * ", "
    end

    desc "Desc2"
    dep :step1
    input :float, :float, "Float"
    task :step2 => :string do |f|
      step(:step1).load + " " + f.to_s
    end

    desc "Desc2_fixed"
    dep :step1, :array => %w(a b)
    input :float, :float, "Float"
    task :step2_fixed => :string do
    end

    desc 'Desc3'
    task_alias :step3, UsageWorkflow, :step2

    desc "Desc3"
    dep :step3, :array => %w(a b)
    task :step3_fixed => :string do
    end
  end


  def test_workflow_usage
    assert_match "evaluate if the documentation", UsageWorkflow.usage
  end

  def test_task_usage
    assert_match "Desc2", UsageWorkflow.tasks[:step2].usage(UsageWorkflow)
    assert_match "--array", UsageWorkflow.tasks[:step2].usage(UsageWorkflow)
    assert_match "Desc2_fixed", UsageWorkflow.tasks[:step2_fixed].usage(UsageWorkflow)
    assert_match "Desc3", UsageWorkflow.tasks[:step3].usage(UsageWorkflow)
    assert_match "--array", UsageWorkflow.tasks[:step3].usage(UsageWorkflow)
  end

  def test_task_input_fixed
    assert_match "Desc2_fixed", UsageWorkflow.tasks[:step2_fixed].usage(UsageWorkflow)
    refute_match "--array", UsageWorkflow.tasks[:step2_fixed].usage(UsageWorkflow)
    assert_match "Desc3", UsageWorkflow.tasks[:step3_fixed].usage(UsageWorkflow)
    refute_match "--array", UsageWorkflow.tasks[:step3_fixed].usage(UsageWorkflow)
  end
end

