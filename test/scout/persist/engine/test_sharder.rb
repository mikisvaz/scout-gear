require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/persist'

class TestSharder < Test::Unit::TestCase
  def test_shard_open

    TmpFile.with_file do |tmpfile|
      sharder = Sharder.new tmpfile, true, :HDB do |key|
        key.to_s[-1]
      end

      sharder["key-a"] = "a"
      sharder["key-b"] = "b"
      assert_equal "a", sharder["key-a"]
      assert_equal "b", sharder["key-b"]

      sharder = Sharder.new tmpfile, true, :HDB
      sharder.shard_function = proc do |key|
        key.split("-").last
      end

      assert_equal "a", sharder["key-a"]
      assert_equal "b", sharder["key-b"]

      assert_equal 2, sharder.persistence_path.glob("*").select{|f| f.include?("shard-") }.length
    end
  end
end

