require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
class TestTSVIndex < Test::Unit::TestCase
  def load_segment_data(data)
    tsv = TSV.open(data, type: :list, :sep=>":", :cast => proc{|e| e =~ /(\s*)(_*)/; ($1.length..($1.length + $2.length - 1))})

    tsv = tsv.add_field "Start" do |key, values|
      values["Range"].first
    end

    tsv = tsv.add_field "End" do |key, values|
      values["Range"].last
    end

    tsv = tsv.slice ["Start", "End"]
 
    tsv
  end

  def test_index
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
      index = TSV.index(filename, :target => "ValueB", :fields => ["OtherID"])
      assert_equal 'B', index["a"]
      assert_nil index["B"]
    end
  end

  def test_from_tsv
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double#:merge=:concat
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A|b    B    Id3|a
row2    a    b    id3
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename)
      index = TSV.index(tsv, :target => "ValueB")
      assert_equal 'b', index["a"]
      assert_equal 'B', index["B"]
      assert_equal 'b', index["b"]

      index = tsv.index(:target => "ValueB")
      assert_equal 'b', index["a"]
      assert_equal 'B', index["B"]
      assert_equal 'b', index["b"]


      index = TSV.index(tsv, :target => "ValueB", :fields => "OtherID")
      assert_equal 'B', index["a"]
      assert_nil index["B"]

      index = tsv.index(:target => "ValueB", :fields => "OtherID")
      assert_equal 'B', index["a"]
      assert_nil  index["B"]
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
      index = TSV.index(filename, :target => "ValueB", :persist => true, bar: true)
      assert_equal 'b', index["row1"]
      assert_equal 'b', index["a"]
      assert_equal 'b', index["aaa"]
      assert_equal 'B', index["A"]
    end
  end

  def test_range_index
    data =<<-EOF
# 012345678901234567890
#ID:Range
a:   ______
b: ______
c:    _______
d:  ____
e:    ______
f:             ___
g:         ____
    EOF
    TmpFile.with_file(data) do |datafile|
      tsv = load_segment_data(datafile)
      f   = tsv.range_index("Start", "End", :persist => true)

      assert_equal %w(), f[0].sort
      assert_equal %w(b), f[1].sort
      assert_equal %w(), f[20].sort
      assert_equal %w(), f[(20..100)].sort
      assert_equal %w(a b d), f[3].sort
      assert_equal %w(a b c d e), f[(3..4)].sort
    end
  end

  def test_pos_index
    data =<<-EOF
# 012345678901234567890
#ID:Range
a:   ______
b: ______
c:    _______
d:  ____
e:    ______
f:             ___
g:         ____
    EOF
    TmpFile.with_file(data) do |datafile|
      tsv = load_segment_data(datafile)
      f   = tsv.pos_index("Start", :persist => true)

      assert_equal %w(), f[0].sort
      assert_equal %w(a c d e), f[(2..4)].sort
    end
  end

  def test_range_index_persistent
    data =<<-EOF
# 012345678901234567890
#ID:Range
a:   ______
b: ______
c:    _______
d:  ____
e:    ______
f:             ___
g:         ____
    EOF
    TmpFile.with_file(data) do |datafile|
      load_segment_data(datafile)
      TmpFile.with_file(load_segment_data(datafile).to_s) do |tsvfile|
        f = TSV.range_index(tsvfile, "Start", "End", :persist => true)

        assert_equal %w(), f[0].sort
        assert_equal %w(b), f[1].sort
        assert_equal %w(), f[20].sort
        assert_equal %w(), f[(20..100)].sort
        assert_equal %w(a b d), f[3].sort
        assert_equal %w(a b c d e), f[(3..4)].sort
      end
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

