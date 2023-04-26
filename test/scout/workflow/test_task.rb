require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestTask < Test::Unit::TestCase
  def _test_basic_task
    task = Task.setup do |s=""|
      (self + s).length
    end

    assert_equal 4, task.exec_on("1234")
    assert_equal 6, task.exec_on("1234","56")
  end

  def _test_step
    task = Task.setup do |s=""|
      s.length
    end

    s = task.job('test', ['12'])
    assert_equal 2, s.run
  end

  def _test_override_inputs
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :input1, :string
      task :step1 => :string do |i| i end

      dep :step1, :input1 => 1
      input :input2, :string
      task :step2 => :string do |i| i end
    end

    job = wf.job(:step2, :input1 => 2)
    assert_equal Task::DEFAULT_NAME, job.name
    assert_not_equal Task::DEFAULT_NAME, job.step(:step1).name
  end

  def _test_override_inputs_block
    Log.severity = 0
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :input1, :string
      task :step1 => :string do |i| i end

      dep :step1 do |id,options|
        {:inputs => {:input1 => 1}}
      end
      input :input2, :string
      task :step2 => :string do |i| i end
    end

    job = wf.job(:step2, :input1 => 2)
    assert_equal Task::DEFAULT_NAME, job.name
    assert_not_equal Task::DEFAULT_NAME, job.step(:step1).name
  end

  def test_task_override_dep
    Log.severity = 0
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :input1, :integer
      task :step1 => :integer do |i| i end

      dep :step1
      input :input2, :integer, "Integer", 3
      task :step2 => :integer do |i| i * step(:step1).load end
    end
    wf.directory = tmpdir.var.jobs.TaskInputs

    assert_equal 6, wf.job(:step2, :input1 => 2, :input2 => 3).run

    step1_job = wf.job(:step1, :input1 => 6)
    assert_equal 18, wf.job(:step2, :input1 => 2, "TaskInputs#step1" => step1_job).run

    assert_equal 18, wf.job(:step2, :input1 => 2, "TaskInputs#step1" => step1_job).run

    assert_equal 18, wf.job(:step2, "TaskInputs#step1" => step1_job).run
  end
end

