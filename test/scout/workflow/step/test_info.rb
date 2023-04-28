require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')
require 'scout/workflow'

class TestStepInfo < Test::Unit::TestCase
  def test_dependency
    sss 0 do
      TmpFile.with_file do |tmpdir|
        Path.setup(tmpdir)
        tmpfile = tmpdir.test_step
        step1 = Step.new tmpfile.step1, ["12"] do |s|
          s.length
        end

        assert_equal 2, step1.exec
        assert_equal 2, step1.run

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
end
