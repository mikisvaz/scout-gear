require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/workflow'

class TestStepChildren < Test::Unit::TestCase
  def test_child
    TmpFile.with_file do |tmpfile|
      step = Step.new tmpfile, ["12"] do |s|
        pid = child do
          Open.write(self.file(:somefile), 'TEST')
        end
        Process.waitpid pid
        s.length
      end
      step.type = :integer

      assert_equal 2, step.run
      assert_equal 1, step.info[:children_pids].length
      assert_include step.files, 'somefile'
    end
  end

end

