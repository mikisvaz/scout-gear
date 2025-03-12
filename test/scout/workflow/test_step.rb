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

  def test_dependency_load
    tmpfile = tmpdir
    step1 = Step.new tmpdir.test_task1.step1, ["12"] do |s|
      s.length
    end

    step2 = Step.new tmpdir.test_task2.step2 do 
      step1 = dependencies.first
      step1.inputs.first + " has " + step1.load.to_s + " characters"
    end

    step2.dependencies = [step1]

    step2.run

    assert_equal "12 has 2 characters", step2.run

    new_step = Step.new step2.path

    assert_equal "12 has 2 characters", new_step.run
    assert_equal 2, new_step.step(:test_task1).run
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

    step1.clean
    res =  step1.run(false)
    refute IO === res
    step1.join

    step1.clean
    res =  step1.run(true)
    assert IO === res
    step1.join
    step1.clean

    step1.clean
    res =  step1.run(:no_load)
    assert res.nil?
    step1.clean

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

    stream = step2.run(true)
    assert step1.streaming?
    assert step2.streaming?

    lines = []
    while line = stream.gets
      lines << line
    end

    stream.join
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

    stream = step3.run(true)
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
    io = step4.run(true)
    Log::ProgressBar.with_bar severity: 0 do |b|
      while line = io.gets
        b.tick
        lines << line.strip
      end
    end
    io.close

    assert_equal times, lines.length
  end

  def test_fork_stream_fork
    tmpfile = tmpdir.test_step

    times = 10_000
    sleep = 0.1 / times

    step1 = Step.new tmpfile.step1, [times, sleep] do |times,sleep|
      sleep 1
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

    step4.recursive_clean
    step4.fork
    assert Array === step4.load
    assert_equal times, step4.load.size
  end

  def test_dependency_canfail
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

  def test_semaphore

    tmpfile = tmpdir.test_step
    step1 = Step.new tmpfile.step1 do |s|
      sleep 2
      "done1"
    end

    step2 = Step.new tmpfile.step2 do 
      sleep 2
      "done2"
    end

    step1.dependencies = []
    step2.dependencies = []

    ScoutSemaphore.with_semaphore(1) do |sem|
      step1.fork(false, sem)
      step2.fork(false, sem)
      sleep 1
      assert((step1.status.to_sym == :queue) || (step2.status.to_sym == :queue))
      step1.join
      step2.join
      assert_equal "done2", step2.run
    end

  end

end
