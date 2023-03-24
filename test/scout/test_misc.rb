require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestMisc < Test::Unit::TestCase
  def test_in_dir
    TmpFile.with_file do |tmpdir|
      Misc.in_dir tmpdir do
        assert_equal tmpdir, FileUtils.pwd
      end
    end
  end
end

