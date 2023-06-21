require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestWorkflowDefinition < Test::Unit::TestCase
  def test_function_task
    wf = Workflow.annonymous_workflow do
      self.name = "StringLength"
      def self.str_length(s)
        s.length
      end

      input :string, :string
      task :str_length => :integer
    end
    assert_equal 5, wf.job(:str_length, :string => "12345").run
  end
end

