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
end

