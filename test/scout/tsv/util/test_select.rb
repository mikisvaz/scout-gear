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

  def test_select_invert
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

    s = tsv.select("ValueA" => 'a')

    assert_equal ['row1'], s.keys

    s = tsv.select({"ValueA" => 'a'}, true)

    assert_equal ['row2'], s.keys
  end

  def test_select_values
    content =<<-'EOF'
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11    B1|B11
row2    A2|A22    B2|B22
    EOF

    tsv = TSV.open(content)

    assert TSV.select("row1", tsv["row1"], "A1")
    refute TSV.select("row2", tsv["row2"], "A1")
    assert TSV.select("row2", tsv["row2"], "A2")

    assert TSV.select("row1", tsv["row1"], "B1")
    refute TSV.select("row2", tsv["row2"], "B1")

    refute TSV.select("row1", tsv["row1"], "B1", invert: true)
    assert TSV.select("row2", tsv["row2"], "B1", invert: true)

    assert TSV.select("row1", tsv["row1"], {"ValueB" => "B1"})
    refute TSV.select("row2", tsv["row2"], {"ValueB" => "B1"})

    tsv.with_unnamed do
      assert TSV.select("row1", tsv["row1"], {"ValueB" => "B1"}, fields: tsv.fields)
      refute TSV.select("row2", tsv["row2"], {"ValueB" => "B1"}, fields: tsv.fields)
    end

    assert TSV.select("row1", tsv["row1"], "B1", field: "ValueB")
    refute TSV.select("row2", tsv["row2"], "B1", field: "ValueB")
  end
end

