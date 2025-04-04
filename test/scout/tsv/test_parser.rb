require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
class TestTSVParser < Test::Unit::TestCase

  def test_parse_line
    line = (0..10).to_a * "\t"
    key, values = TSV.parse_line(line)

    assert_equal "0", key
    assert_equal (1..10).collect{|v| v.to_s }, values
  end

  def test_parse_line_key
    line = (0..10).to_a * "\t"
    key, values = TSV.parse_line(line, key: 2)
    
    assert_equal "2", key
    assert_equal %w(0 1 3 4 5 6 7 8 9 10), values
  end


  def test_parse_double
    line = (0..10).collect{|v| v == 0 ? v : [v,v] * "|" } * "\t"
    key, values = TSV.parse_line(line, type: :double, cast: :to_i)

    assert_equal "0", key
    assert_equal (1..10).collect{|v| [v,v] }, values
  end

  def ___test_benchmark
    num = 10_000
    txt = num.times.inject(nil) do |acc,i|
      (acc.nil? ? "" : acc << "\n") << (0..10).collect{|v| v == 0 ? i : [v,v] * "|" } * "\t"
    end 

    txt = StringIO.new(([txt] * (10))*"\n")
    Misc.benchmark 5 do
      txt.rewind
      #Misc.profile do
      data = TSV.parse_stream(txt, fix: true, type: :double, bar: true, merge: :concat)
      assert_equal num, data.size
      assert_equal 20, data['1'][0].length
    end
  end

  def test_parse_stream
    lines =<<-EOF
1 2 3 4 5
11 12 13 14 15
    EOF

    lines = StringIO.new lines

    data = TSV.parse_stream lines, sep: " "
    assert_equal data["1"], %w(2 3 4 5)
  end

  def test_parse_stream_block
    lines =<<-EOF
1 2 3 4 5
11 12 13 14 15
    EOF

    lines = StringIO.new lines

    sum = 0
    res = TSV.parse_stream(lines, sep: " ") do |k,values|
      sum += values.inject(0){|acc,i| acc += i.to_i }
    end
    assert_equal 68, sum
  end

  def test_parse_header
    header =<<-EOF
#: :sep=" "
#Key ValueA ValueB
k A B
    EOF
    header = StringIO.new header

    assert_equal "Key", TSV.parse_header(header)[1]
  end

  def test_parse
    header =<<-EOF
#: :sep=" "#:type=:double
#Key ValueA ValueB
k a|A b|B
    EOF
    header = StringIO.new header

    tsv = TSV.parse(header)
    assert_equal 'a', tsv['k'][0][0]
  end

  def test_parse_head
    content =<<-EOF
#: :sep=" "#:type=:double
#Key ValueA ValueB
k a|A b|B
k1 a|A b|B
k2 a|A b|B
k3 a|A b|B
k4 a|A b|B
    EOF
    content = StringIO.new content

    tsv = TSV.parse(content, :head => 2)
    assert_equal 2, tsv.keys.length

    content.rewind
    tsv = TSV.parse(content, :head => 3)
    assert_equal 3, tsv.keys.length
  end

  def test_parse_tsv_grep
    content =<<-EOF
#: :sep=" "#:type=:double
#Key ValueA ValueB
k a|A b|B
k1 a|A b|B
k2 a|A b|B
k3 a|A b|B
k4 a|A b|B
    EOF
    content = StringIO.new content

    tsv = TSV.parse(content, :tsv_grep => ["k3","k4"])
    assert_equal %w(k3 k4), tsv.keys.sort
  end

  def test_parse_fields
    content =<<-EOF
#: :sep=" "#:type=:double
#Key ValueA ValueB
k a|A b|B
    EOF
    content = StringIO.new content

    tsv = TSV.parse(content, fields: %w(ValueB))
    assert_equal [%w(b B)], tsv['k']
    assert_equal %w(ValueB), tsv.fields

    content.rewind

    tsv = TSV.parse(content, fields: %w(ValueB ValueA))
    assert_equal [%w(b B), %w(a A)], tsv['k']
    assert_equal %w(ValueB ValueA), tsv.fields

    content.rewind

    tsv = TSV.parse(content, fields: %w(ValueB Key))
    assert_equal [%w(b B), %w(k)], tsv['k']
  end

  def test_parse_flat
    content =<<-EOF
#: :sep=" "#:type=:flat
#Key ValueA
row1 a aa aaa
row2 b bb bbb
    EOF

    tsv = TSV.open(content)
    assert_equal %w(a aa aaa), tsv["row1"]
    tsv = TSV.open(content, :fields => ["ValueA"])
    assert_equal %w(a aa aaa), tsv["row1"]
  end

  def test_parse_key
    content =<<-EOF
#: :sep=" "#:type=:double
#Key ValueA ValueB
k a|A b|B
    EOF
    content = StringIO.new content

    tsv = TSV.parse(content, key_field: "ValueB")
    assert_equal %w(b B), tsv.keys
    assert_equal %w(a A), tsv["B"][1]

    content.rewind

    tsv = TSV.parse(content, key_field: "ValueB", one2one: true, type: :double)
    assert_equal %w(b B), tsv.keys
    assert_equal %w(A), tsv["B"][1]

    content.rewind

    tsv = TSV.parse(content, key_field: "ValueB", one2one: true, type: :list)
    assert_equal %w(b B), tsv.keys
    assert_equal "a", tsv["b"][1]
    assert_equal "A", tsv["B"][1]
    assert_equal "k", tsv["b"][0]
    assert_equal "k", tsv["B"][0]

    content.rewind

    tsv = TSV.parse(content, key_field: "ValueB", one2one: true, type: :list)
    assert_equal %w(b B), tsv.keys
    assert_equal "A", tsv["B"][1]
  end

  def test_parser_class
    content =<<-EOF
Key ValueA ValueB
k a|A b|B
    EOF
    content = StringIO.new content

    parser = TSV::Parser.new content, sep: " ", header_hash: ''

    assert_equal "Key", parser.key_field

    values = []
    parser.traverse fields: %w(ValueB), type: :double do |k,v|
      values << [k,v]
    end

    assert_equal [["k", [%w(b B)]]], values
  end

  def test_parser_traverse_all
    content =<<-EOF
Key ValueA ValueB
k a|A b|B
    EOF
    content = StringIO.new content

    parser = TSV::Parser.new content, sep: " ", header_hash: ''

    assert_equal "Key", parser.key_field

    values = []
    parser.traverse key_field: "ValueA", fields: :all, type: :double do |k,v|
      values << v
    end

    assert_include values.flatten, 'a'
  end


  def test_parse_persist_serializer
    content =<<-EOF
Key ValueA ValueB
k 1 2
    EOF
    content = StringIO.new content

    TmpFile.with_file do |db|
      data = ScoutCabinet.open db, true, "HDB"
      TSV.parse content, sep: " ", header_hash: '', data: data, cast: :to_i, type: :list
      assert_equal [1, 2], data["k"]
    end

    TmpFile.with_file do |db|
      content.rewind
      data = ScoutCabinet.open db, true, "HDB"
      TSV.parse content, sep: " ", header_hash: '', data: data, cast: :to_i, type: :list, serializer: :float_array
      assert_equal [1.0, 2.0], data["k"]
    end
  end

  def test_merge
    content =<<-EOF
#: :type=:double
#PMID:Sentence number:TF:TG	Transcription Factor (Associated Gene Name)	Target Gene (Associated Gene Name)	Sign	Negation	PMID
24265317:3:NR1H3:FASN	NR1H3	FASN			24265317
17522048:0:NR1H3:FASN	NR1H3	FASN	+		17522048
19903962:0:NR1H3:FASN	NR1H3	FASN			19903962
19903962:7:NR1H3:FASN	NR1H3	FASN			19903962
22183856:4:NR1H3:FASN	NR1H3	FASN			22183856
22641099:4:NR1H3:FASN	NR1H3	FASN	+		22641099
23499676:8:NR1H3:FASN	NR1H3	FASN	+		23499676
11790787:5:NR1H3:FASN	NR1H3	FASN			11790787
11790787:7:NR1H3:FASN	NR1H3	FASN	+		11790787
11790787:9:NR1H3:FASN	NR1H3	FASN	+		11790787
11790787:11:NR1H3:FASN	NR1H3	FASN			11790787
17522048:1:NR1H3:FASN	NR1H3	FASN	+		17522048
17522048:3:NR1H3:FASN	NR1H3	FASN			17522048
22160584:1:NR1H3:FASN	NR1H3	FASN			22160584
22160584:5:NR1H3:FASN	NR1H3	FASN	+		22160584
22160584:8:NR1H3:FASN	NR1H3	FASN	+		22160584
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, key_field: "Transcription Factor (Associated Gene Name)", fields: ["Target Gene (Associated Gene Name)", "Sign", "PMID"], merge: true, one2one: true, type: :double)
      assert_equal 16, tsv["NR1H3"]["Sign"].length
    end
  end

  def test_load_stream
    content =<<-EOF
#Key    ValueA    ValueB
k    a|A    b|B
k1    a|A    b|B
k2    a|A    b|B
k3    a|A    b|B
k4    a|A    b|B
    EOF
    content = StringIO.new content.gsub('    ', "\t")

    TmpFile.with_file do |tmp_logfile|
      old_logfile = Log.logfile
      Log.logfile(tmp_logfile)
      TmpFile.with_file do |persistence|
        data = ScoutCabinet.open persistence, true
        tsv = Log.with_severity(0) do
          TSV.parse(content, data: data)
        end
        assert_equal %w(b B), tsv["k"]["ValueB"]
        assert_equal %w(a A), tsv["k4"]["ValueA"]
      end
      Log.logfile(old_logfile)
      assert Open.read(tmp_logfile).include?("directly into")
    end
  end

  def test_acceptable_parser_options
    assert_include TSV.acceptable_parser_options, :namespace
  end
end
