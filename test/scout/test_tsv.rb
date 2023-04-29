require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestTSV < Test::Unit::TestCase
  def test_open
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double#:merge=:concat
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    a    a    id3
    EOF

    content2 =<<-'EOF'
#: :sep=/\s+/#:type=:double#:merge=:concat
#Id    ValueA    ValueB    OtherID
row3    a|aa|aaa    b    Id1|Id2
row4    A    B    Id3
row4    a    a    id3
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename)
    end

    TmpFile.with_file(content2) do |filename|
      TSV.open(filename, :data => tsv)
    end
    assert 
  end
end

