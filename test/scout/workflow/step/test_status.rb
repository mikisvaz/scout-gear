require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestStepStatus < Test::Unit::TestCase
  def test_dependency
    tmpfile = tmpdir.test_step
    step1 = Step.new tmpfile.step1, ["12"] do |s|
      s.length
    end

    step2 = Step.new tmpfile.step2 do 
      step1 = dependencies.first
      step1.inputs.first + " has " + step1.load.to_s + " characters"
    end

    step2.dependencies = [step1]

    Misc.with_env "SCOUT_UPDATE", "true" do
      step2.run
      assert step2.updated?

      sleep 0.1
      step1.clean
      step1.run
      refute step2.updated?
    end
  end

end

