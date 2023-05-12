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

  def test_streaming
    tmpfile = tmpdir.test_step

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

    step1.run
    step1.join
    assert step1.path.read.end_with? "line-#{times-1}\n"

    step1.clean

    stream = step2.exec
    lines = []
    while line = stream.gets
      lines << line
    end
    assert_equal times/2, lines.length

    stream = step2.run
    assert step1.streaming?
    assert step2.streaming?

    lines = []
    while line = stream.gets
      lines << line
    end

    assert step1.path.read.end_with? "line-#{times-1}\n"
    assert_equal times/2, lines.length
    assert_equal times/2, step2.join.path.read.split("\n").length
  end

  def test_streaming_duplicate
    tmpfile = tmpdir.test_step

    times = 10_000
    sleep = 0.01 / times

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

    step3 = Step.new tmpfile.step3 do 
      step1, step2 = dependencies
      stream = step2.stream

      Open.open_pipe do |sin|
        while line = stream.gets
          num = line.split("-").last
          next if num.to_i % 2 == 1
          sin.puts line
        end
      end
    end
    step3.type = :array
    step3.dependencies = [step1, step2]

    step3.recursive_clean

    stream = step3.run
    out = []
    while l = stream.gets
      out << l
    end
    assert_equal times/2, out.length
  end

  def test_fork_stream
    tmpfile = tmpdir.test_step

    times = 10_000
    sleep = 0.1 / times

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
      stream = step1.stream

      Open.open_pipe do |sin|
        while line = stream.gets
          num = line.split("-").last
          next if num.to_i % 2 == 1
          sin.puts "S2: " + line
        end
      end
    end
    step2.type = :array
    step2.dependencies = [step1]

    step3 = Step.new tmpfile.step3 do 
      step1 = dependencies.first
      stream = step1.stream

      Open.open_pipe do |sin|
        while line = stream.gets
          num = line.split("-").last
          next if num.to_i % 2 == 0
          sin.puts "S3: " + line
        end
      end
    end
    step3.type = :array
    step3.dependencies = [step1]


    step4 = Step.new tmpfile.step4 do 
      step2, step3 = dependencies

      mutex = Mutex.new
      Open.open_pipe do |sin|
        t2 = Thread.new do
          stream2 = step2.stream
          while line = stream2.gets
            sin.puts line
          end
        end

        t3 = Thread.new do
          stream3 = step3.stream
          while line = stream3.gets
            sin.puts line
          end
        end
        t2.join
        t3.join
      end
    end
    step4.type = :array
    step4.dependencies = [step2, step3]

    lines = []
    io = step4.run
    Log::ProgressBar.with_bar severity: 0 do |b|
      while line = io.gets
        b.tick
        lines << line.strip
      end
    end
    io.close

    assert_equal times, lines.length
  end
end
