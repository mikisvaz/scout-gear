require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestStepProgress < Test::Unit::TestCase
  def test_monitor_stream

    TmpFile.with_file do |tmpfile|
      items = %w(foo bar baz)
      lines = []
      step = Step.new tmpfile, ["12"] do |s|
        file = file('test')
        Open.write file, items * "\n"
        s = file.open
        self.monitor_stream s, bar: 3 do |line|
          lines  << line.strip
        end
      end
      step.type = :text

      res = step.run(:stream)
      res.read
      res.join
      assert_equal items, lines
    end
  end
end

