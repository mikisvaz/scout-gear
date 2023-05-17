require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
class TestTSVSelect < Test::Unit::TestCase
  def test_select
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    AA    BB    Id33
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename, :persist => true)
    end

    s = tsv.select do |k,v|
      k.include? "2"
    end

    assert_equal ['row2'], s.keys
  end

  def test_reorder
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double
#Id    ValueA    ValueB    OtherID
row1    a1|a2    b1|b2    Id1|Id2
row2    A1|A3    B1|B3    Id1|Id3
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename)
    end

    r = tsv.reorder "OtherID", %w(ValueB Id)

    assert_equal %w(row1 row2), r["Id1"]["Id"]
    assert_equal %w(row2), r["Id3"]["Id"]
  end

  def test_reorder_list
    content =<<-'EOF'
#: :sep=/\s+/#:type=:list
#Id    ValueA    ValueB    OtherID
row1    a1    b1    Id1
row2    A1    B1    Id1
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename)
    end

    r = tsv.reorder "ValueB"

    assert_equal "row1", r["b1"]["Id"]
    assert_equal "row2", r["B1"]["Id"]
  end

  def test_reorder_single
    content =<<-'EOF'
#: :sep=/\s+/#:type=:single
#Id    ValueA
row1    a1
row2    A1
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename)
    end

    r = tsv.reorder "ValueA"

    assert_equal "row1", r["a1"]
    assert_equal "row2", r["A1"]
  end
end

