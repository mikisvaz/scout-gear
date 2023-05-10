require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'

class TestTSVPersist < Test::Unit::TestCase
  def test_persist
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double#:merge=:concat
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    a    a    id3
    EOF


    tsv = Persist.persist("TEST Persist TSV", :tsv) do 
      TmpFile.with_file(content) do |filename|
        TSV.open(filename)
      end
    end

    assert_include tsv.keys, 'row1'
    assert_include tsv.keys, 'row2'

    tsv = Persist.persist("TEST Persist TSV", :tsv) do 
      TmpFile.with_file(content) do |filename|
        TSV.open(filename)
      end
    end


    assert_nothing_raised do
      tsv = Persist.persist("TEST Persist TSV", :tsv) do 
        raise
      end
    end

    assert_include tsv.keys, 'row1'
    assert_include tsv.keys, 'row2'
  end
end

