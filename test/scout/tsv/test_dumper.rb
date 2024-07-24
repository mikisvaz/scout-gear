require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'

class TestTSVDumper < Test::Unit::TestCase
  def test_dumper
    dumper = TSV::Dumper.new :key_field => "Key", :fields => %w(Field1 Field2), :type => :double
    dumper.init
    dumper.add "a", [["1", "11"], ["2", "22"]]
    txt=<<-EOF
#: :type=:double
#Key\tField1\tField2
a\t1|11\t2|22
    EOF
    dumper.close
    assert_equal txt, dumper.stream.read
  end

  def test_set_stream
    io = StringIO.new
    dumper = TSV::Dumper.new :key_field => "Key", :fields => %w(Field1 Field2), :type => :double
    dumper.set_stream io
    dumper.init
    dumper.add "a", [["1", "11"], ["2", "22"]]
    txt=<<-EOF
#: :type=:double
#Key\tField1\tField2
a\t1|11\t2|22
    EOF
    dumper.close
    io.rewind
    assert_equal txt, io.read
  end

  def test_to_s
    tsv = TSV.setup({}, :key_field => "Key", :fields => %w(Field1 Field2), :type => :double)
    tsv["a"] = [["1", "11"], ["2", "22"]]
    txt=<<-EOF
#: :type=:double
#Key\tField1\tField2
a\t1|11\t2|22
    EOF
    assert_equal txt, tsv.to_s
  end

  def test_raise
    dumper = TSV::Dumper.new :key_field => "Key", :fields => %w(Field1 Field2), :type => :double
    dumper.init
    t = Thread.new do
      dumper.add "a", [["1", "11"], ["2", "22"]]
      dumper.abort ScoutException
    end

    assert_raise ScoutException do
      TSV.open(dumper.stream, bar: true)
    end
  end

  def test_to_s_sort
    tsv = TSV.setup({}, :key_field => "Key", :fields => %w(Field1 Field2), :type => :double)
    tsv["b"] = [["2", "22"], ["3", "33"]]
    tsv["a"] = [["1", "11"], ["2", "22"]]
    txt=<<-EOF
#: :type=:double
#Key\tField1\tField2
a\t1|11\t2|22
b\t2|22\t3|33
    EOF
    assert_equal txt, tsv.to_s(keys: tsv.keys.sort)
  end

  def test_filename
    tsv = datadir_test.person.marriages.tsv
    assert tsv.filename

    tsv2 = TSV.open(tsv.dumper_stream)
    assert tsv2.filename
  end

  def test_compact
    dumper = TSV::Dumper.new :key_field => "Key", :fields => %w(Field1 Field2), :type => :double, compact: true
    dumper.init
    t = Thread.new do
      dumper.add "a", [["1", "11"], ["2", "22"]]
      dumper.add "b", [[nil, nil], ["3", "33"]]
      dumper.close
    end

    tsv = TSV.open(dumper.stream)
    assert_equal [], tsv["b"]["Field1"]

    dumper = TSV::Dumper.new :key_field => "Key", :fields => %w(Field1 Field2), :type => :double, compact: false
    dumper.init
    t = Thread.new do
      dumper.add "a", [["1", "11"], ["2", "22"]]
      dumper.add "b", [[nil, nil], ["3", "33"]]
      dumper.close
    end

    tsv = TSV.open(dumper.stream)
    assert_equal ["", ""], tsv["b"]["Field1"]
  end

end

