require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/workflow'
class TestStepProvenance < Test::Unit::TestCase
  def test_prov_report
    tmpfile = tmpdir.test_step
    step1 = Step.new tmpfile.step1, ["12"] do |s|
      s.length
    end

    step2 = Step.new tmpfile.step2 do
      step1 = dependencies.first
      step1.inputs.first + " has " + step1.load.to_s + " characters"
    end

    step2.dependencies = [step1]

    step2.run

    assert_include Step.prov_report(step2), 'step1'
    assert_include Step.prov_report(step2), 'step2'
  end

  def __test_input_dependencies
    wf = Workflow.annonymous_workflow "TaskInputDepProv" do
      input :value1, :integer
      task :number1 => :integer do |i| i end

      input :value2, :integer
      task :number2 => :integer do |i| i end

      input :number1, :integer
      input :number2, :integer
      task :sum => :integer do |i1,i2| i1 + i2 end

      dep :number1, :value1 => 1
      dep :number2, :value1 => 2
      dep_task :my_sum, self, :sum, :number1 => :number1, :number2 => :number2

    end
    job = wf.job(:my_sum)

    ppp Step.prov_report(job)

  end
end

