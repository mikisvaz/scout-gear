require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')
require 'scout/workflow'

class TestStepInfo < Test::Unit::TestCase
  def test_benchmark
    i = {a:1, b: [1,2], c: "String"}
    times = 100000
    Misc.benchmark(times) do
      Marshal.dump(i)
    end
    Misc.benchmark(times) do
      i.to_json
    end
  end

  def test_dependency
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

  def test_inputs_marshal
    TmpFile.with_file do |tmpdir|
      Path.setup(tmpdir)
      tmpfile = tmpdir.test_step

      path = tmpfile.foo
      step1 = Step.new tmpfile.step1, [path] do |s|
        s.length
      end

      step1.run

      refute Path === step1.info[:inputs][0]

    end
  end

  def test_messages
    TmpFile.with_file do |tmpdir|
      Path.setup(tmpdir)
      tmpfile = tmpdir.test_step
      step1 = Step.new tmpfile.step1, ["12"] do |s|
        log :msg, "Message1"
        log :msg, "Message2"
        s.length
      end

      step1.run

      assert_equal %w(Message1 Message2), step1.messages
    end
  end

  def test_overriden_fixed
    TmpFile.with_file("HELLO") do |file|
      wf = Module.new do
        extend Workflow

        self.name = "TestWF"

        task :message => :string do
          "HI"
        end

        dep :message
        task :say => :string do
          "I say #{step(:message).load}"
        end

        task_alias :say_hello, self, :say, "TestWF#message" => file, :not_overriden => true
      end

      assert_equal "I say HI", wf.job(:say).run

      job1 = wf.job(:say, "TestWF#message" => file)
      assert_equal "I say HELLO", job1.run

      job2 = wf.job(:say_hello)
      assert_equal "I say HELLO", job2.run

      assert job1.overriden?
      refute job2.overriden?

      assert job1.overriden_deps.any?
      refute job2.overriden_deps.any?
    end
  end
end
