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

  def test_as_jobname
    wf = Workflow.annonymous_workflow do
      self.name = "CallName"
      input :name, :string, "Name to call", nil, :jobname => true
      task :call_name => :string do |name|
        "Hi #{name}"
      end
    end
    assert_equal "Hi Miguel", wf.job(:call_name, "Miguel").run
    assert_equal "Hi Cleia", wf.job(:call_name, "Miguel", name: "Cleia").run
    assert_equal "Miguel", wf.job(:call_name, "Miguel", name: "Cleia").clean_name
    assert_equal "Cleia", wf.job(:call_name, name: "Cleia").clean_name
  end
end

