require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/workflow'

class TestWorkflowUtil < Test::Unit::TestCase
  def test_annonymous_workflow
    wf = Workflow.annonymous_workflow do
      task :length => :integer do
        self.length
      end
    end
    bindings = "12345"
    assert_equal 5, wf.tasks[:length].exec_on(bindings)
  end
end

