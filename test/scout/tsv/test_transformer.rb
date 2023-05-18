require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
class TestTSVTransformer < Test::Unit::TestCase
  def test_traverse
    content =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11    B1|B11
row2    A2|A22    B2|B22
    EOF

    TmpFile.with_file(content) do |file|
      parser = TSV::Parser.new file
      dumper = TSV::Dumper.new :key_field => "Key", :fields => ["Values"], type: :flat
      dumper.init

      trans = TSV::Transformer.new parser, dumper
      dumper = trans.traverse do |k,values|
        [k, values.flatten]
      end

      tsv = trans.tsv
      assert_equal %w(A1 A11 B1 B11), tsv['row1']
    end
  end

  def test_each
    content =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11    B1|B11
row2    A2|A22    B2|B22
    EOF

    TmpFile.with_file(content) do |file|
      parser = TSV::Parser.new file
      dumper = TSV::Dumper.new :key_field => "Key", :fields => ["Values"], type: :flat
      dumper.init

      trans = TSV::Transformer.new parser, dumper
      dumper = trans.each do |k,values|
        values.replace values.flatten
      end

      trans["row3"] = %w(A3 A33)

      tsv = trans.tsv
      assert_equal %w(A1 A11 B1 B11), tsv['row1']
      assert_equal %w(A3 A33), tsv['row3']
    end
  end

  def test_no_dumper_no_parser
    content =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11    B1|B11
row2    A2|A22    B2|B22
    EOF

    TmpFile.with_file(content) do |file|
      trans = TSV::Transformer.new file
      trans.key_field = "Key"
      trans.fields = ["Values"]
      trans.type = :flat
      trans.sep = "\t"

      trans.each do |k,values|
        values.replace values.flatten
      end

      trans["row3"] = %w(A3 A33)

      tsv = trans.tsv
      assert_equal %w(A1 A11 B1 B11), tsv['row1']
      assert_equal %w(A3 A33), tsv['row3']
    end
  end


end

