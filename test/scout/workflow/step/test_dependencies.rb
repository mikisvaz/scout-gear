require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/named_array'
class TestStepDependencies < Test::Unit::TestCase
  def test_recursive_inputs
    tmpfile = tmpdir.test_step
    step1 = Step.new tmpfile.step1, NamedArray.setup(["12"], %w(input1)) do |s|
      s.length
    end

    step2 = Step.new tmpfile.step2, NamedArray.setup([2], %w(input2)) do |times|
      step1 = dependencies.first
      (step1.inputs.first + " has " + step1.load.to_s + " characters") * times
    end

    step2.dependencies = [step1]

    assert_equal 2, step2.inputs["input2"]
    assert_equal "12", step2.recursive_inputs["input1"]
    assert_equal 2, step2.inputs[:input2]
    assert_equal "12", step2.recursive_inputs[:input1]
  end

  def test_can_fail
    tmpfile = tmpdir.test_step
    step1 = Step.new tmpfile.step1, NamedArray.setup(["12"], %w(input1)) do |s|
      raise ScoutException
    end

    step2 = Step.new tmpfile.step2, NamedArray.setup([2], %w(input2)) do |times|
      step1 = dependencies.first
      if step1.error?
        (step1.inputs.first + " has unknown characters") * times
      else
        (step1.inputs.first + " has " + step1.load.to_s + " characters") * times
      end
    end

    step2.dependencies = [step1]
    step2.compute = {step1.path => [:canfail] }

    assert_include step2.run, "unknown"
  end

  def test_can_stream
    tmpfile = tmpdir.test_step

    Misc.with_env "SCOUT_EXPLICIT_STREAMING", "true" do
      times = 10_000
      sleep = 1 / times

      step1 = Step.new tmpfile.step1, [times, sleep] do |times,sleep|
        Open.open_pipe do |sin|
          times.times do |i|
            sin.puts "line-#{i}"
            sleep sleep
          end
        end
      end
      step1.type = :array

      step2 = Step.new tmpfile.step2 do 
        step1 = dependencies.first
        raise ScoutException unless step1.streaming?
        stream = step1.stream

        Open.open_pipe do |sin|
          while line = stream.gets
            num = line.split("-").last
            next if num.to_i % 2 == 1
            sin.puts line
          end
        end
      end
      step2.type = :array
      step2.dependencies = [step1]

      assert_raise ScoutException do
        step2.run
      end

      step2.recursive_clean

      step2.compute = {step1.path => [:stream]}

      assert_nothing_raised do
        step2.run
      end
    end
  end
end

