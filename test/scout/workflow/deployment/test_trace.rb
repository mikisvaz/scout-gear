require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'

class TestWorkflowTrace < Test::Unit::TestCase
  def test_trace
    m = Module.new do
      extend Workflow
      self.name = "TestWF"

      input :option1
      task :step1 do end

      dep :step1
      input :option2
      task :step2 do end
    end

    job = m.job(:step2)
    job.run
    assert_equal 1, Workflow.trace([job])["TestWF#step1"]["Calls"]
  end
end

