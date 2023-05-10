require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestTSV < Test::Unit::TestCase
  def test_open_with_data
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
      TSV.open(filename, :persist => false)
    end

    TmpFile.with_file(content2) do |filename|
      TSV.open(filename, :data => tsv)
    end

    assert_include tsv.keys, 'row4'
    assert_include tsv.keys, 'row1'
  end

  def test_open_persist
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double#:merge=:concat
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    a    a    id3
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename, :persist => true)
    end

    assert tsv.respond_to?(:persistence_class)
    assert_equal TokyoCabinet::HDB, tsv.persistence_class

    assert_include tsv.keys, 'row1'
    assert_include tsv.keys, 'row2'
  end

  def test_open_persist_in_situ
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double#:merge=:concat
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    a    a    id3
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename, :persist => false)
    end

    assert_include tsv.keys, 'row1'
    assert_include tsv.keys, 'row2'
    assert_equal %w(A a), tsv["row2"][0]

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename, :persist => true, :merge => true)
    end

    assert tsv.respond_to?(:persistence_class)
    assert_equal TokyoCabinet::HDB, tsv.persistence_class

    assert_include tsv.keys, 'row1'
    assert_include tsv.keys, 'row2'
    assert_equal %w(A a), tsv["row2"][0]
  end
end

