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

  def test_index_from_flat
    content =<<-'EOF'
#: :sep=" "#:type=:flat
#Id    ValueA
row1    a aa aaa
row2    b bb bbb
    EOF

    TmpFile.with_file(content) do |filename|
      index = TSV.index(filename, :target => "Id")
      assert_equal "row1", index["aa"]
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

  def test_index_fields
    content =<<-EOF
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(File.open(filename), :sep => /\s+/, :key_field => "OtherID", :persist => false)
      index = tsv.index(:persist => true, :persist_update => true)
      assert index["row1"].include? "Id1"
      assert_equal "OtherID", index.fields.first
    end
  end


  def test_simple_index_key_field
    text=<<-EOF
#: :sep=' '
#Y X
y x
yy xx
    EOF

    TmpFile.with_file(text) do |tmp|
      assert_equal "Y", TSV.open(tmp).index(:target => "X", :fields => ["Y"]).key_field
      assert_equal "Y", TSV.index(tmp, :target => "X", :fields => ["Y"]).key_field
    end
  end

  def test_pos_and_range_index
    content =<<-EOF
#Id	ValueA    ValueB    Pos1    Pos2
row1    a|aa|aaa    b    0|10    10|30
row2    A    B    30   35
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(File.open(filename), type: :double, sep: /\s+/)
      index = tsv.pos_index("Pos1")
      assert_equal ["row1"], index[10]

      index = tsv.range_index("Pos1", "Pos2")
      assert_equal ["row1"], index[20]
    end
  end


  def test_index_static_persist
    content =<<-EOF
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b|A    Id1
row2    A    a|B    Id3
row3    A    a|B    Id4
    EOF

    TmpFile.with_file(content) do |filename|
      index = TSV.index(filename, :target => "OtherID", :sep => /\s+/, :order => true, :persist => false)
      assert_equal "Id1", index['a']
      assert_equal "Id3", index['A']
      assert_equal "OtherID", index.fields.first

      index = TSV.index(filename, :target => "OtherID", :sep => /\s+/, :order => true, :persist => true)
      assert_equal "Id1", index['a']
      assert_equal "Id3", index['A']
      assert_equal "OtherID", index.fields.first

      Open.write(filename, Open.read(filename).sub(/row1.*Id1\n/,''))

      index = TSV.index(filename, :target => "OtherID", :sep => /\s+/, :order => true, :persist => true)
      assert_equal "Id1", index['a']
      assert_equal "Id3", index['A']
      assert_equal "OtherID", index.fields.first
      assert index.include?('aaa')

      index = TSV.index(filename, :target => "OtherID", :sep => /\s+/, :order => true, :persist => false)
      assert ! index.include?('aaa')
    end
  end


end

