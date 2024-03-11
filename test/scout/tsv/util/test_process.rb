require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
class TestTSVProcess < Test::Unit::TestCase
  def test_process
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    AA    BB    Id33
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename)
    end

    tsv.process "ValueA" do |v|
      v.collect{|e| e.upcase }
    end

    assert_equal %w(A AA AAA), tsv["row1"][0]
  end

  def test_add_field
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    AA    BB    Id33
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename)
    end

    tsv.add_field "ValueC" do |k,v|
      v[0].collect{|e| e.gsub("a", "c").gsub("A", "C") }
    end

    assert_equal %w(c cc ccc), tsv["row1"]["ValueC"]
    assert_equal %w(C CC), tsv["row2"]["ValueC"]
  end

  def test_add_field_double_empty
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    AA    BB    Id33
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename)
    end

    tsv.add_field "ValueC" do |k,v|
      nil
    end

    assert_equal %w(), tsv["row1"]["ValueC"]
  end

  def test_remove_duplicates
    content =<<-EOF
#Id    ValueA    ValueB    OtherID
row1    a|A|a|a    b|B|b|    Id1|Id2|Id1|Id1
row2    aa|aa|AA|AA    b1|b2|B1|B2    Id1|Id1|Id2|Id2
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :sep => /\s+/)
      assert_equal %w(a A a), tsv.remove_duplicates["row1"]["ValueA"]
      assert tsv.remove_duplicates["row1"]["ValueB"].include?("")
    end

  end

end

