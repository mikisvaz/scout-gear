module Misc
  def self.pid_alive?(pid)
    !! Process.kill(0, pid) rescue false
  end
  def self.benchmark(repeats = 1, message = nil)
    require 'benchmark'
    res = nil
    begin
      measure = Benchmark.measure do
        repeats.times do
          res = yield
        end
      end
      if message
        puts "#{message }: #{ repeats } repeats"
      else
        puts "Benchmark for #{ repeats } repeats"
      end
      puts measure
    rescue Exception
      puts "Benchmark aborted"
      raise $!
    end
    res
  end

  def self.profile(options = {})
    require 'ruby-prof'
    profiler = RubyProf::Profile.new
    profiler.start
    begin
      res = yield
    rescue Exception
      puts "Profiling aborted"
      raise $!
    ensure
      result = profiler.stop
      printer = RubyProf::FlatPrinter.new(result)
      printer.print(STDOUT, options)
    end

    res
  end
end
