require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'

class TestTSVTraverse < Test::Unit::TestCase
  def test_tsv_traverse_double
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    AA    BB    Id33
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename, :persist => true)
    end

    res = {}
    tsv.traverse :key, %w(OtherID ValueB) do |k,v|
      res[k] = v
    end
    assert_equal [%w(Id3 Id33), %w(B BB)], res["row2"]

    res = {}
    tsv.traverse :key, %w(OtherID ValueB), type: :list do |k,v|
      res[k] = v
    end
    assert_equal ["Id3", "B"], res["row2"]

    res = {}
    tsv.traverse "OtherID", %w(Id ValueB), one2one: true do |k,v|
      res[k] = v
    end
    assert_equal [[nil], %w(BB)], res["Id33"]

    res = {}
    tsv.traverse "OtherID", %w(Id ValueB), one2one: true, type: :list do |k,v|
      res[k] = v
    end
    assert_equal ["row2", "B"], res["Id3"]
    assert_equal [nil, "BB"], res["Id33"]

    tsv.traverse "OtherID", %w(Id ValueB), one2one: false, type: :list do |k,v|
      res[k] = v
    end
    assert_equal ["row2", "B"], res["Id3"]
    assert_equal [nil, "BB"], res["Id33"]

    res = {}
    key_name, field_names = tsv.traverse "OtherID" do |k,v|
      res[k] = v
    end
    assert_equal "OtherID", key_name
    assert_equal %w(Id ValueA ValueB), field_names
  end

  def test_tsv_traverse_all
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    AA    BB    Id33
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename, :persist => true)
    end

    all_values = []
    tsv.traverse "ValueA", :all do |k,v|
      all_values.concat(v)
    end
    assert_include all_values.flatten, "row1"
    assert_include all_values.flatten, "a"
    assert_include all_values.flatten, "aaa"

    all_values = []
    tsv.traverse "Id", :all do |k,v|
      all_values.concat(v)
    end
    assert_include all_values.flatten, "row1"
    assert_include all_values.flatten, "a"
    assert_include all_values.flatten, "aaa"
  end

  def test_tsv_traverse_list
    content =<<-'EOF'
#: :sep=/\s+/#:type=:list
#Id    ValueA    ValueB    OtherID
row1    a    b    Id1
row2    A    B    Id3
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename, :persist => true)
    end

    res = {}
    tsv.traverse :key, %w(OtherID ValueB) do |k,v|
      res[k] = v
    end
    assert_equal ["Id3", "B"], res["row2"]

    res = {}
    tsv.traverse :key, %w(OtherID ValueB), type: :double do |k,v|
      res[k] = v
    end
    assert_equal [%w(Id3), %w(B)], res["row2"]

    res = {}
    tsv.traverse :key, %w(OtherID ValueB), type: :flat do |k,v|
      res[k] = v
    end
    assert_equal %w(Id3 B), res["row2"]
  end

  def test_tsv_traverse_single
    content =<<-'EOF'
#: :sep=/\s+/#:type=:single
#Id    ValueA
row1    a
row2    A
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename, :persist => true)
    end

    res = {}
    tsv.traverse "ValueA", %w(Id) do |k,v|
      res[k] = v
    end
    assert_equal "row1", res["a"]

    res = {}
    tsv.traverse "ValueA", %w(Id), type: :double do |k,v|
      res[k] = v
    end
    assert_equal [["row1"]], res["a"]
  end

end

