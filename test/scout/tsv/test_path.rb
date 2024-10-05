require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestTsvPath < Test::Unit::TestCase
  def test_tsv_open_persist
    content =<<-'EOF'
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    a    a    id3
    EOF


    tsv = nil
    TmpFile.with_file(content) do |filename|
      Path.setup(filename)
      tsv = filename.tsv persist: true, merge: true, type: :list, sep: /\s+/
      assert_equal %w(ValueA ValueB OtherID), tsv.fields
      tsv = filename.tsv persist: true, merge: true, type: :list, sep: /\s+/
      assert_equal %w(ValueA ValueB OtherID), tsv.fields
    end
  end
end

