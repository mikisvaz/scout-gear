module Misc
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
end
