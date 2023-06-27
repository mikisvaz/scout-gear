require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/workflow'
class TestTaskDependencies < Test::Unit::TestCase
  def test_task_override_dep_exec
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :input1, :integer
      task :step1 => :integer do |i| i end

      dep :step1
      input :input2, :integer, "Integer", 3
      task :step2 => :integer do |i| i * step(:step1).load end
    end

    assert_equal 6, wf.job(:step2, :input1 => 2, :input2 => 3).exec

    step1_job = wf.job(:step1, :input1 => 6)
    assert_equal 18, wf.job(:step2, :input1 => 2, "TaskInputs#step1" => step1_job).exec

    assert_equal 18, wf.job(:step2, :input1 => 2, "TaskInputs#step1" => step1_job).exec

    assert_equal [step1_job.path], wf.job(:step2, :input1 => 2, "TaskInputs#step1" => step1_job).overriden_deps.collect{|d| d.path }

    assert_equal 18, wf.job(:step2, "TaskInputs#step1" => step1_job).exec
  end

  def test_task_override_dep
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :input1, :integer
      task :step1 => :integer do |i| i end

      dep :step1
      input :input2, :integer, "Integer", 3
      task :step2 => :integer do |i| i * step(:step1).load end
    end

    assert_equal 6, wf.job(:step2, :input1 => 2, :input2 => 3).run

    step1_job = wf.job(:step1, :input1 => 6)
    assert_equal 18, wf.job(:step2, :input1 => 2, "TaskInputs#step1" => step1_job).run

    assert_equal 18, wf.job(:step2, :input1 => 2, "TaskInputs#step1" => step1_job).run

    assert_equal 18, wf.job(:step2, "TaskInputs#step1" => step1_job).run
  end

  def test_input_dep
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :v1, :integer
      input :v2, :integer
      task :sum => :integer do |v1,v2|
        v1 + v2
      end

      input :input1, :integer
      task :step1 => :integer do |i| i end

      input :input2, :integer
      task :step2 => :integer do |i| i end

      dep :step1, :input1 => 2
      dep :step2, :input2 => 3
      dep :sum, :v1 => :step1, :v2 => :step2
      task :my_sum => :integer do
        dependencies.last.load
      end

      dep :my_sum
      task :double => :integer do
        step(:my_sum).load * 2 
      end
    end

    job = wf.job(:my_sum)
    assert_equal 5, job.run
    assert_equal Task::DEFAULT_NAME, job.name

    job = wf.job(:double)
    assert_equal Task::DEFAULT_NAME, job.name

    step1 = wf.job(:step1, :input1 => 3)
    assert_equal 3, step1.run
    job = wf.job(:double, "TaskInputs#step1" => step1)
    assert_equal 12, job.run
    assert_not_equal Task::DEFAULT_NAME, job.name

    step1 = wf.job(:step1, :input1 => 4)
    assert_equal 4, step1.run
    job = wf.job(:double, "TaskInputs#step1" => step1)
    assert_equal 14, job.run
    assert_not_equal Task::DEFAULT_NAME, job.name
  end

  def test_input_dep_override
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :v1, :integer
      input :v2, :integer
      task :sum => :integer do |v1,v2|
        v1 + v2
      end

      input :input1, :integer
      task :step1 => :integer do |i| i end

      input :input2, :integer
      task :step2 => :integer do |i| i end

      dep :step1
      dep :step2
      task :my_sum => :integer do
        dependencies.inject(0){|acc,d| acc += d.load }
      end
    end

    step2 = wf.job(:step2, :input2 => 4)
    job = wf.job(:my_sum, :input1 => 2, :input2 => 3, "TaskInputs#step2"=> step2)
    assert_equal 6, job.exec

    job = wf.job(:my_sum, :input1 => 2, :input2 => 3)
    assert_equal 5, job.run

    TmpFile.with_file(4) do |file|
      job = wf.job(:my_sum, :input1 => 2, :input2 => 3, "TaskInputs#step2"=> file)
      assert_equal 6, job.run
      assert_not_equal Task::DEFAULT_NAME, job.name
    end
  end

  def test_input_rename
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :v1, :integer
      input :v2, :integer
      task :sum => :integer do |v1,v2|
        v1 + v2
      end

      input :vv1, :integer
      input :vv2, :integer
      dep :sum, :v1 => :vv1, :v2 => :vv2
      task :my_sum => :integer do
        dependencies.last.load
      end
    end

    job = wf.job(:my_sum, :vv1 => 2, :vv2 => 3)
    assert_equal 5, job.run
  end

  def test_defaults_in_dep_block
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :v1, :integer
      input :v2, :integer
      task :sum => :integer do |v1,v2|
        v1 + v2
      end

      input :vv1, :integer
      input :vv2, :integer, nil, 3
      dep :sum, :v1 => :placeholder, :v2 => :placeholder do |jobname,options,dependencies|
        raise "Non-numeric value where integer expected" unless Numeric === options[:vv1]
        {inputs: {v1: options[:vv1], v2: options[:vv2]} }
      end
      task :my_sum => :integer do
        dependencies.last.load
      end
    end

    job = wf.job(:my_sum, :vv1 => "2")
    assert_equal 5, job.run
  end

  def test_dependency_jobname
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :v1, :integer
      input :v2, :integer
      task :sum => :integer do |v1,v2|
        v1 + v2
      end

      input :vv1, :integer
      input :vv2, :integer
      dep :sum, :v1 => :vv1, :v2 => :vv2, :jobname => "OTHER_NAME"
      task :my_sum => :integer do
        dependencies.last.load
      end
    end

    job = wf.job(:my_sum, "TEST_NAME", :vv1 => 2, :vv2 => 3)
    assert_equal 5, job.run
    assert_equal "TEST_NAME", job.clean_name
    assert_equal "OTHER_NAME", job.step(:sum).clean_name
  end

  def test_no_param_last_job
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :v1, :integer
      input :v2, :integer
      task :sum => :integer do |v1,v2|
        v1 + v2
      end

      dep :sum
      task :my_sum => :integer do
        dependencies.last.load
      end
    end

    job = wf.job(:my_sum, :v1 => 2, :v2 => "3")
    assert_equal 5, job.run
    refute_equal Task::DEFAULT_NAME, job.name
  end

  def test_no_param_last_job_block
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :v1, :integer
      input :v2, :integer
      task :sum => :integer do |v1,v2|
        v1 + v2
      end

      dep :sum do |jobname,options|
        {inputs: options}
      end
      task :my_sum => :integer do
        dependencies.last.load
      end
    end

    job = wf.job(:my_sum, :v1 => 2, :v2 => "3")
    assert_equal 5, job.run
    refute_equal Task::DEFAULT_NAME, job.name
  end


  def test_override_inputs_block
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :input1, :string
      task :step1 => :string do |i| i end

      dep :step1, :input1 => 1  do |id,options|
        {:inputs => options}
      end
      task :step2 => :string do |i| step(:step1).load end
    end

    job = wf.job(:step2, :input1 => 2)
    assert_equal 1, job.run
    assert_equal Task::DEFAULT_NAME, job.name
    assert_not_equal Task::DEFAULT_NAME, job.step(:step1).name
  end

  def test_default_inputs_in_block
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :input1, :string
      task :step1 => :string do |i| i end

      dep :step1  do |id,options|
        {}
      end
      task :step2 => :string do |i| step(:step1).load end
    end

    job = wf.job(:step2, "SOME_NAME", :input1 => 2)
    assert_equal "SOME_NAME", job.step(:step1).clean_name
    assert_equal 2, job.run
  end

  def test_override_inputs_block_array
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :input1, :string
      task :step1 => :string do |i| i end

      dep :step1, :input1 => 1  do |id,options|
        [{:inputs => options}]
      end
      input :input2, :string
      task :step2 => :string do |i| step(:step1).load end
    end

    job = wf.job(:step2, :input1 => 2)
    assert_equal 1, job.run
    assert_equal Task::DEFAULT_NAME, job.name
    assert_not_equal Task::DEFAULT_NAME, job.step(:step1).name
  end

  def test_override_inputs
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :input1, :string
      task :step1 => :string do |i| i end

      dep :step1, :input1 => 1
      input :input2, :string
      task :step2 => :string do |i| step(:step1).load end
    end

    job = wf.job(:step2, :input1 => 2)
    assert_equal 1, job.run
    assert_equal Task::DEFAULT_NAME, job.name
    assert_not_equal Task::DEFAULT_NAME, job.step(:step1).name
  end

  def test_non_default_inputs
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :input1, :integer, "", 1
      input :input2, :integer, "", 0
      task :step1 => :string do |i1,i2| i1 + i2 end

      dep :step1, :input2 => 1
      task :step2 => :string do |i| step(:step1).load end

      dep :step2
      task :step3 => :string do |i| step(:step1).load end
    end

    job = wf.job(:step3, :input1 => 1)
    assert_equal Task::DEFAULT_NAME, job.name
    assert_not_equal Task::DEFAULT_NAME, job.step(:step1).name
    assert_equal 2, job.run

    job = wf.job(:step3, :input1 => 2)
    assert_equal 3, job.run


    job = wf.job(:step3)
    assert_equal Task::DEFAULT_NAME, job.name
    assert_not_equal Task::DEFAULT_NAME, job.step(:step1).name
  end

  def test_can_fail
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :input1, :integer, "", 1
      task :step1 => :string do |i1| 
        if i1 < 0
          raise ScoutException
        else
          i1
        end
      end

      dep :step1, :canfail => true
      task :step2 => :string do |i|
        if step(:step1).error?
          0
        else
          step(:step1).load 
        end
      end
    end

    assert_equal 1, wf.job(:step2, :input1 => 1).run
    assert_equal 2, wf.job(:step2, :input1 => 2).run
    assert_equal 0, wf.job(:step2, :input1 => -2).run
  end

end

