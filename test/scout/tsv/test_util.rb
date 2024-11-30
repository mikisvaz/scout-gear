require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
class TestTSVUtil < Test::Unit::TestCase
  def test_open_persist
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double#:merge=:concat
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    a    a    id3
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename, :sep => " " )
    end
    assert_equal %w(row1 row2), tsv.collect{|k,v| k }
    refute NamedArray === tsv.collect{|k,v| v }.first
    tsv.unnamed = false
    assert NamedArray === tsv.collect{|k,v| v }.first
    assert "row1", tsv["row1"].key
  end

end

