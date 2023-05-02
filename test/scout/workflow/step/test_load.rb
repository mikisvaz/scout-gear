require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/workflow/step'

class TestStepLoad < Test::Unit::TestCase
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

    step2.recursive_clean
    step2.run

    new_step2 = Step.load(step2.path)

    assert_equal "12 has 2 characters", new_step2.load
    assert_equal "12 has 2 characters", new_step2.run
    assert_equal 2, new_step2.dependencies.first.run
    assert_equal "12", new_step2.dependencies.first.inputs.first
  end

  def test_relocate
    wf = Workflow.annonymous_workflow "RelocateWorkflow" do
      input :input1, :string
      task :step1 => :string do |input1|
        input1
      end

      dep :step1
      task :step2 => :string do
        step(:step1).load.reverse
      end
    end

    step2 = wf.job(:step2, :input1 => "TEST")
    step1 = step2.step(:step1)

    step2.run
    new_step2 = Step.load(step2.path)
    TmpFile.with_file do |dir|
      Misc.in_dir dir do
        Path.setup(dir)
        Open.mv step1.path, dir.var.jobs.RelocateWorkflow.step1[File.basename(step1.path)]
        Open.mv step1.info_file, dir.var.jobs.RelocateWorkflow.step1[File.basename(step1.info_file)]

        new_step2 = Step.load(step2.path)
        assert_equal "TEST".reverse, new_step2.load
        assert_equal "TEST", new_step2.dependencies.first.load
      end
    end

  end
end

