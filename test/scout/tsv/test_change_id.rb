require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
class TestChangeID < Test::Unit::TestCase
  def test_simple_reorder
    content1 =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11    B1|B11
row2    A2|A22    B2|B22
    EOF

    tsv = TSV.open StringIO.new(content1)

    res = tsv.change_key "ValueA"
    assert_equal ["row1"], res["A1"]["ID"]
    assert_equal ["row1"], res["A11"]["ID"]
    assert_equal ["row2"], res["A2"]["ID"]
  end

  def test_simple_reorder_file
    content1 =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11    B1|B11
row2    A2|A22    B2|B22
    EOF

    TmpFile.with_file(content1) do |file1|
      res = TSV.change_key file1, "ValueA"
      assert_equal ["row1"], res["A1"]["ID"]
      assert_equal ["row1"], res["A11"]["ID"]
      assert_equal ["row2"], res["A2"]["ID"]
      assert_equal ["B1","B11"], res["A1"]["ValueB"]

      res = TSV.change_key file1, "ValueA", one2one: true
      assert_equal ["row1"], res["A1"]["ID"]
      assert_equal ["row1"], res["A11"]["ID"]
      assert_equal ["row2"], res["A2"]["ID"]
      assert_equal ["B1"], res["A1"]["ValueB"]
    end
  end

  def test_change_key_identifiers
    content1 =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11    B1|B11
row2    A2|A22    B2|B22
    EOF

    identifiers_content =<<-EOF
#: :sep=" "
#ID    ValueC    ValueD
row1    C1|C11    D1|D11
row2    C2|C22    D2|D22
    EOF


    tsv = TSV.open StringIO.new(content1)
    identifiers = TSV.open StringIO.new(identifiers_content)

    res = tsv.change_key "ValueC", identifiers: identifiers
    assert_equal ["row1"], res["C1"]["ID"]
    assert_equal ["row1"], res["C11"]["ID"]
    assert_equal ["row2"], res["C2"]["ID"]
  end

  def test_change_id_identifiers
    content1 =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11    B1|B11
row2    A2|A22    B2|B22
    EOF

    identifiers_content =<<-EOF
#: :sep=" "
#ID    ValueC    ValueD
row1    C1|C11    D1|D11
row2    C2|C22    D2|D22
    EOF


    tsv = TSV.open StringIO.new(content1)
    identifiers = TSV.open StringIO.new(identifiers_content)

    res = tsv.change_id "ValueA", "ValueC", identifiers: identifiers
    assert_equal ["C1","C11"], res["row1"]["ValueC"]
    assert_equal ["C2","C22"], res["row2"]["ValueC"]
  end
end

