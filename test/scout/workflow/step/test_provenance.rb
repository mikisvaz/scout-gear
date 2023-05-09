require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/workflow'
class TestStepProvenance < Test::Unit::TestCase
  def test_true
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
end

