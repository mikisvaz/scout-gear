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

  def test_parse_double
    line = (0..10).collect{|v| v == 0 ? v : [v,v] * "|" } * "\t"
    key, values = TSV.parse_line(line, type: :double, cast: :to_i)

    assert_equal "0", key
    assert_equal (1..10).collect{|v| [v,v] }, values
  end

  def __test_benchmark
    num = 10_000
    txt = num.times.inject(nil) do |acc,i|
      (acc.nil? ? "" : acc << "\n") << (0..10).collect{|v| v == 0 ? i : [v,v] * "|" } * "\t"
    end 

    txt = StringIO.new(([txt] * (10))*"\n")
    Misc.benchmark 1 do
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
end
