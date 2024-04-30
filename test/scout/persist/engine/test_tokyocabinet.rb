require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestScoutCabinet < Test::Unit::TestCase
  def test_open
    TmpFile.with_file do |tmpfile|
      db = ScoutCabinet.open(tmpfile)
      db["a"] = 1
      assert_equal "1", db["a"]
      db.close

      db = ScoutCabinet.open(tmpfile, false)
      assert_equal "1", db["a"]
    end
  end
end

