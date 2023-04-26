require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestWorkflowStep < Test::Unit::TestCase

  def test_step
    TmpFile.with_file do |tmpfile|
      step = Step.new tmpfile, ["12"] do |s|
        s.length
      end
      step.type = :integer

      assert_equal 2, step.run
    end
  end

  def test_dependency
    Log.with_severity 0 do
      tmpfile = tmpdir.test_step
      step1 = Step.new tmpfile.step1, ["12"] do |s|
        s.length
      end

      step2 = Step.new tmpfile.step2 do 
        step1 = dependencies.first
        step1.inputs.first + " has " + step1.load.to_s + " characters"
      end

      step2.dependencies = [step1]


      assert_equal "12 has 2 characters", step2.run
      assert_equal "12 has 2 characters", step2.run
    end
  end
end
