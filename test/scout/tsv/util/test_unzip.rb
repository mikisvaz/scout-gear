require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
class TestTSVUnzip < Test::Unit::TestCase
  def test_unzip
    content1 =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11    B1|B11
row2    A2|A22    B2|B22
    EOF

    tsv = TSV.open(content1)
    unzip = tsv.unzip("ValueA", delete: true)
    assert_equal "B1", unzip["row1:A1"]["ValueB"]
    assert_equal "B22", unzip["row2:A22"]["ValueB"]
  end

  def test_unzip_list
    content1 =<<-EOF
#: :sep=" "#:type=:list
#ID    ValueA    ValueB
row1    A1    B1
row2    A2    B2
    EOF

    tsv = TSV.open(content1)
    unzip = tsv.unzip("ValueA", delete: true)
    assert_equal "B1", unzip["row1:A1"]["ValueB"]
    assert_equal "B2", unzip["row2:A2"]["ValueB"]
  end

  def test_unzip_merge
    content1 =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11|A11    B1|B11|B11.1
row2    A2|A22|A11    B2|B22|B22.2
    EOF

    tsv = TSV.open(content1)
    unzip = tsv.unzip("ValueA", delete: true, merge: true)
    assert_equal ["B1"], unzip["row1:A1"]["ValueB"]
    assert_equal ["B11", "B11.1"], unzip["row1:A11"]["ValueB"]
    assert_equal ["B22"], unzip["row2:A22"]["ValueB"]
  end
end

