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
row2    A2|A22|A22    B2|B22|B22.2
    EOF

    tsv = TSV.open(content1)
    unzip = tsv.unzip("ValueA", delete: true, merge: true)
    assert_equal ["B1"], unzip["row1:A1"]["ValueB"]
    assert_equal ["B11", "B11.1"], unzip["row1:A11"]["ValueB"]
    assert_equal ["B22", "B22.2"], unzip["row2:A22"]["ValueB"]
  end

  def test_unzip_merge_stream
    content1 =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11|A11    B1|B11|B11.1
row2    A2|A22|A22    B2|B22|B22.2
    EOF

    tsv = TSV.open(content1)
    unzip = tsv.unzip("ValueA", delete: true, merge: true, target: :stream).tsv
    assert_equal ["B1"], unzip["row1:A1"]["ValueB"]
    assert_equal ["B11", "B11.1"], unzip["row1:A11"]["ValueB"]
    assert_equal ["B22", "B22.2"], unzip["row2:A22"]["ValueB"]
  end

  def test_unzip_merge_stream_parser
    content1 =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11|A11    B1|B11|B11.1
row2    A2|A22|A22    B2|B22|B22.2
    EOF

    TmpFile.with_file(content1) do |filename|
      unzip = TSV.unzip(filename, "ValueA", delete: true, merge: true, target: :stream).tsv
      assert_equal ["B1"], unzip["row1:A1"]["ValueB"]
      assert_equal ["B11", "B11.1"], unzip["row1:A11"]["ValueB"]
      assert_equal ["B22", "B22.2"], unzip["row2:A22"]["ValueB"]
    end
  end

  def test_unzip_merge_stream_parser_one2many
    content1 =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11|A11    B1|B11|B11.1
row2    A2|A22|A22    B2|B22|B22.2
    EOF

    TmpFile.with_file(content1) do |filename|
      unzip = TSV.unzip(filename, "ValueA", delete: true, merge: true, target: :stream, one2one: false).tsv
      assert_equal ["B1", "B11", "B11.1"], unzip["row1:A1"]["ValueB"].uniq
      assert_equal ["B1", "B11", "B11.1"], unzip["row1:A11"]["ValueB"].uniq
    end
  end


  def test_unzip_target
    content1 =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11|A11    B1|B11|B11.1
row2    A2|A22|A22    B2|B22|B22.2
    EOF

    tsv = TSV.open(content1)
    unzip = TSV.setup({}, :key_field => "Key", :fields => %w(ValueA ValueB))
    tsv.unzip("ValueA", delete: true, merge: true, target: unzip)
    assert_equal ["B1"], unzip["row1:A1"]["ValueB"]
    assert_equal ["B11", "B11.1"], unzip["row1:A11"]["ValueB"]
    assert_equal ["B22", "B22.2"], unzip["row2:A22"]["ValueB"]
  end

  def test_unzip_replicates
   content =<<-EOF
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b|bb|bbb    Id1|Id2|Id3
row2    A    B    Id3
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :sep => /\s+/)

      assert_equal 4, tsv.unzip_replicates.length
      assert_equal %w(aa bb Id2), tsv.unzip_replicates["row1(1)"]
    end
  end


  def test_unzip_zip
    content =<<-EOF
#Id    ValueA    ValueB    OtherID
row1    a|A|a|a    b|B|b|    Id1|Id2|Id1|Id1
row2    aa|aa|AA|AA    b1|b2|B1|B2    Id1|Id1|Id2|Id2
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :sep => /\s+/)
      assert_equal ["b", "b", ""], tsv.unzip("ValueA", merge: true)["row1:a"]["ValueB"]
      assert_equal ["b", "b", "", "B"].sort, tsv.unzip("ValueA", merge: true).zip(true)["row1"]["ValueB"].sort
    end

  end

end

