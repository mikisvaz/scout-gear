require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
class TestTSVTransformer < Test::Unit::TestCase
  def test_filename
    content =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11    B1|B11
row2    A2|A22    B2|B22
    EOF

    TmpFile.with_file(content) do |file|
      parser = TSV::Parser.new file
      dumper = TSV::Dumper.new :key_field => "Key", :fields => ["Values"], type: :flat, :filename => parser.options[:filename]
      dumper.init

      trans = TSV::Transformer.new parser, dumper
      dumper = trans.traverse do |k,values|
        [k, values.flatten]
      end

      tsv = trans.tsv
      assert_include tsv.filename, File.dirname(file)

      assert_equal %w(A1 A11 B1 B11), tsv['row1']
    end
    
  end

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
      trans["row3"] = %w(A3 A33)
      dumper = trans.each do |k,values|
        values.replace values.flatten
      end

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

      trans["row3"] = %w(A3 A33)

      trans.each do |k,values|
        values.replace values.flatten
      end

      tsv = trans.tsv
      assert_equal %w(A1 A11 B1 B11), tsv['row1']
      assert_equal %w(A3 A33), tsv['row3']
    end
  end

  def test_to_list
    content =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11    B1|B11
row2    A2|A22    B2|B22
    EOF

    tsv = TSV.open(content)
    assert_equal "A1", tsv.to_list["row1"]["ValueA"]
    assert_equal "B2", tsv.to_list["row2"]["ValueB"]
  end

  def test_to_single
    content =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11    B1|B11
row2    A2|A22    B2|B22
    EOF

    tsv = TSV.open(content)
    assert_equal "A1", tsv.to_single["row1"]
    assert_equal "A2", tsv.to_single["row2"]
  end

  def test_to_flat
    content =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11    B1|B11
row2    A2|A22    B2|B22
    EOF

    tsv = TSV.open(content)
    assert_equal %w(A1 A11 B1 B11), tsv.to_flat["row1"]
  end

  def test_to_double
    content =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1    B1
row2    A2    B2
    EOF

    tsv = TSV.open(content)
    assert_equal %w(A1), tsv.to_double["row1"]["ValueA"]
  end
end
