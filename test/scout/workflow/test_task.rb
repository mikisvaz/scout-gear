require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestTask < Test::Unit::TestCase
  def test_basic_task
    task = Task.setup do |s=""|
      (self + s).length
    end

    assert_equal 4, task.exec_on("1234")
    assert_equal 6, task.exec_on("1234","56")
  end

  def test_step
    task = Task.setup do |s=""|
      s.length
    end

    s = task.job('test', ['12'])
    s.clean
    assert_equal 2, s.run
  end

  def __test_benchmark
    tasks = []
    wf = Module.new do
      extend Workflow
      self.name = "TestWF"

      500.times do |i|
        task_name = "task_#{i}"
        last_task_name = "task_#{i-1}"
        if i == 0
          task task_name => :array do
            [task_name]
          end
        else
          dep last_task_name
          task task_name => :array do
            step(last_task_name).load.push(task_name)
          end
        end
      end
    end

    Misc.benchmark(1000) do
      wf.job(:task_499)
    end
  end
end
