require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
class TestTSVStream < Test::Unit::TestCase
  def test_paste_stream
    text1=<<-EOF
#: :sep=" "
#Row LabelA LabelB LabelC
row1 A B C
row2 AA BB CC
row3 AAA BBB CCC
    EOF

    text2=<<-EOF
#: :sep=" "
#Row Labela Labelb 
row1 a b
row2 aa bb
row3 aaa bbb
    EOF

    text3=<<-EOF
#: :sep=" "
#Row LabelC
row1 c
row2 cc
row3 ccc
    EOF

    s1 = StringIO.new text1
    s2 = StringIO.new text2
    s3 = StringIO.new text3
    tsv = TSV.open TSV.paste_streams([s1,s2,s3], :sep => " ", :type => :list)
    assert_equal ["A", "B", "C", "a", "b", "c"], tsv["row1"]
    assert_equal ["AA", "BB", "CC", "aa", "bb", "cc"], tsv["row2"]
    assert_equal ["AAA", "BBB", "CCC", "aaa", "bbb", "ccc"], tsv["row3"]
  end

  def test_paste_stream_sort
    text1=<<-EOF
#: :sep=" "
#Row LabelA LabelB LabelC
row2 AA BB CC
row1 A B C
row3 AAA BBB CCC
    EOF

    text2=<<-EOF
#: :sep=" "
#Row Labela Labelb
row1 a b
row3 aaa bbb
row2 aa bb
    EOF

    text3=<<-EOF
#: :sep=" "
#Row Labelc
row3 ccc
row1 c
row2 cc
    EOF

    s1 = StringIO.new text1
    s2 = StringIO.new text2
    s3 = StringIO.new text3
    tsv = TSV.open TSV.paste_streams([s1,s2,s3], :sep => " ", :type => :list, :sort => true)
    assert_equal "Row", tsv.key_field
    assert_equal %w(LabelA LabelB LabelC Labela Labelb Labelc), tsv.fields
    assert_equal ["A", "B", "C", "a", "b", "c"], tsv["row1"]
    assert_equal ["AA", "BB", "CC", "aa", "bb", "cc"], tsv["row2"]
    assert_equal ["AAA", "BBB", "CCC", "aaa", "bbb", "ccc"], tsv["row3"]
  end

  def test_paste_stream_missing_2
    text1=<<-EOF
#: :sep=" "
#Row LabelA LabelB LabelC
row2 AA BB CC
row1 A B C
    EOF

    text2=<<-EOF
#: :sep=" "
#Row Labela Labelb
row2 aa bb
    EOF

    text3=<<-EOF
#: :sep=" "
#Row Labelc
row3 ccc
row2 cc
    EOF

    s1 = StringIO.new text1
    s2 = StringIO.new text2
    s3 = StringIO.new text3
    tsv = TSV.open TSV.paste_streams([s1,s2,s3], :sep => " ", :type => :list, :sort => true)
    assert_equal "Row", tsv.key_field
    assert_equal %w(LabelA LabelB LabelC Labela Labelb Labelc), tsv.fields
    assert_equal ["A", "B", "C", "", "", ""], tsv["row1"]
    assert_equal ["AA", "BB", "CC", "aa", "bb", "cc"], tsv["row2"]
    assert_equal ["", "", "", "", "", "ccc"], tsv["row3"]
  end

  def test_paste_stream_missing
    text1=<<-EOF
#: :sep=" "
#Row LabelA LabelB LabelC
row2 AA BB CC
row1 A B C
    EOF

    text2=<<-EOF
#: :sep=" "
#Row Labela Labelb
row2 aa bb
    EOF

    text3=<<-EOF
#: :sep=" "
#Row Labelc
row3 ccc
row2 cc
    EOF

    s1 = StringIO.new text1
    s2 = StringIO.new text2
    s3 = StringIO.new text3
    tsv = TSV.open TSV.paste_streams([s1,s2,s3], :sep => " ", :type => :list, :sort => true)
    assert_equal "Row", tsv.key_field
    assert_equal %w(LabelA LabelB LabelC Labela Labelb Labelc), tsv.fields
    assert_equal ["A", "B", "C", "", "", ""], tsv["row1"]
    assert_equal ["AA", "BB", "CC", "aa", "bb", "cc"], tsv["row2"]
    assert_equal ["", "", "", "", "", "ccc"], tsv["row3"]
  end

  def test_paste_stream_missing_3
    text1=<<-EOF
#: :sep=" "
#Row LabelA LabelB LabelC
row2 AA BB CC
row1 A B C
    EOF

    text2=<<-EOF
#: :sep=" "
#Row Labelc
    EOF

    s1 = StringIO.new text1
    s2 = StringIO.new text2
    tsv = TSV.open TSV.paste_streams([s1,s2], :sep => " ", :type => :list, :sort => true)
    assert_equal "Row", tsv.key_field
    assert_equal %w(LabelA LabelB LabelC Labelc), tsv.fields
    assert_equal ["A", "B", "C", ""], tsv["row1"]
    assert_equal ["AA", "BB", "CC", ""], tsv["row2"]
  end

  def test_paste_stream_same_field
    text1=<<-EOF
#: :sep=" "
#Row LabelA
row1 A
row2 AA
    EOF

    text2=<<-EOF
#: :sep=" "
#Row LabelA
row2 AAA
    EOF

    s1 = StringIO.new text1
    s2 = StringIO.new text2
    tsv = TSV.open TSV.paste_streams([s1,s2], :sep => " ", :type => :double, :sort => false, :same_fields => true)
    assert_equal "Row", tsv.key_field
    assert_equal ["AA", "AAA"], tsv["row2"][0]
  end

  def test_paste_stream_nohead
    text1=<<-EOF
row1\tA
row2\tAA
    EOF

    text2=<<-EOF
row2\tAAA
    EOF

    s1 = StringIO.new text1
    s2 = StringIO.new text2
    tsv = TSV.open TSV.paste_streams([s1,s2], :type => :double, :sort => false, :same_fields => true)
    assert_equal ["AA", "AAA"], tsv["row2"][0]
  end

  def test_concat_streams

    text1=<<-EOF
#Key\tValueA
row1\tA
row2\tAA
    EOF

    text2=<<-EOF
#Key\tValueA
row3\tAAA
row2\tBB
    EOF

    s1 = StringIO.new text1
    s2 = StringIO.new text2
    tsv = TSV.open TSV.concat_streams([s1,s2]), :merge => true
    assert_equal ["A"], tsv["row1"][0]
    assert_equal ["AA","BB"], tsv["row2"][0]
    assert_equal ["AAA"], tsv["row3"][0]
  end

end

