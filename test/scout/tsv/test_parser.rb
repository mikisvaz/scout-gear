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

end
