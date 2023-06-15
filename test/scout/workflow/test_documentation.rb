require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestWorkflowDocumentation < Test::Unit::TestCase
  module UsageWorkflow
    extend Workflow
    
    self.name = "UsageWorkflow"

    self.title = "Workflow to test documentation"
    self.description = "Use this workflow to test if the documentation is correctly presented"

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

  def test_usage
    assert_match 'test', UsageWorkflow.documentation[:title]
    assert_match 'presented', UsageWorkflow.documentation[:description]
  end

  def test_documentation_markdown
    doc =<<-EOF
summary

description

# Tasks

## task1

task 1 summary

task 1 description

## task2
task 2 summary

task 2 description
    EOF

    assert_includes Workflow.parse_workflow_doc(doc)[:tasks], 'task1'
    assert_includes Workflow.parse_workflow_doc(doc)[:tasks]['task2'], 'task 2 description'
  end
end

