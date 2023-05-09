require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestTSVIndex < Test::Unit::TestCase
  def test_true
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double#:merge=:concat
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3|a
row2    a    b    id3
    EOF

    TmpFile.with_file(content) do |filename|
      index = TSV.index(filename, :target => "ValueB")
      assert_equal 'b', index["row1"]
      assert_equal 'b', index["a"]
      assert_equal 'b', index["aaa"]
      assert_equal 'B', index["A"]
    end

    TmpFile.with_file(content) do |filename|
      index = TSV.index(filename, :target => "ValueB", :fields => "OtherID")
      assert_equal 'B', index["a"]
      assert_nil index["B"]
    end
  end

  def test_persist
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double#:merge=:concat
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3|a
row2    a    b    id3
    EOF
    tsv = TmpFile.with_file(content) do |filename|
      index = TSV.index(filename, :target => "ValueB", :persist => true)
      assert_equal 'b', index["row1"]
      assert_equal 'b', index["a"]
      assert_equal 'b', index["aaa"]
      assert_equal 'B', index["A"]
    end
  end

  def __test_speed
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double#:merge=:concat
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3|a
row2    a    b    id3
    EOF
    tsv = TmpFile.with_file(content) do |filename|
      Misc.benchmark 1000 do
        TSV.index(filename, :target => "ValueB")
      end
      Misc.benchmark 1000 do
        TSV.index(filename, :target => "ValueB", order: false)
      end
    end
  end
end

