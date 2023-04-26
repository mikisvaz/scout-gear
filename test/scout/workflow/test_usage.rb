require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/workflow'
class TestWorkflowUsage < Test::Unit::TestCase
  module UsageWorkflow
    extend Workflow

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

  def __test_usage
    UsageWorkflow.tasks[:step1].doc
    UsageWorkflow.doc
  end
end

