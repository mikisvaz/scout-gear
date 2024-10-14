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

  def test_paste_streams_repeat
    text1=<<-EOF
YHR055C	856452|856450	YHR055C|YHR055C
YPR161C	856290	YPR161C
YOL138C	853982	YOL138C
YDR395W	852004	YDR395W
YGR129W	853030	YGR129W
YPR165W	856294	YPR165W
YPR098C	856213	YPR098C
YPL015C	856092	YPL015C
YCL050C	850307	YCL050C
YAL069W		YAL069W
    EOF

    text2=<<-EOF
YHR055C	CUP1-2	AAA34541
YHR055C	CUP1-2	AAB68382
YHR055C	CUP1-2	AAS56843
YHR055C	CUP1-2	DAA06748
YHR055C	CUP1-2	AAB68384
YHR055C	CUP1-2	AAT93096
YHR055C	CUP1-2	DAA06746
YPR161C	SGV1	BAA14347
YPR161C	SGV1	AAB59314
YPR161C	SGV1	AAB68058
    EOF

    s1 = StringIO.new text1
    s2 = StringIO.new text2
    tsv = TSV.open(TSV.paste_streams([s1,s2], sort:true, one2one: false), merge: true, one2one: false)
    assert_equal 2, tsv["YHR055C"][0].length
    assert_equal %w(SGV1) * 3, tsv["YPR161C"][2]
  end

  def test_paste_stream_flat
    text1=<<-EOF
#: :sep=" "
#Row LabelA LabelB LabelC
row1 A B C
row2 AA BB CC
row3 AAA BBB CCC
    EOF

    text2=<<-EOF
#: :sep=" "#:type=:flat
#Row Flat
row1 f1 f2 f3
    EOF


    s1 = StringIO.new text1
    s2 = StringIO.new text2
    tsv = TSV.open TSV.paste_streams([s1,s2], :sep => " ", :type => :double)
    assert_include tsv["row1"], %w(f1 f2 f3)
  end
end

