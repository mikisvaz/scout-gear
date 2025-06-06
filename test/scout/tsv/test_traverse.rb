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
    tsv.traverse "OtherID", %w(Id ValueB), one2one: :strict do |k,v|
      res[k] = v
    end
    assert_equal [[nil], %w(BB)], res["Id33"]

    res = {}
    tsv.traverse "OtherID", %w(Id ValueB), one2one: :strict, type: :list do |k,v|
      res[k] = v
    end
    assert_equal ["row2", "B"], res["Id3"]
    assert_equal [nil, "BB"], res["Id33"]

    res = {}
    tsv.traverse "OtherID", %w(Id ValueB), one2one: true, type: :list do |k,v|
      res[k] = v
    end
    assert_equal ["row2", "B"], res["Id3"]
    assert_equal ["row2", "BB"], res["Id33"]


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

  def test_traverse_reorder_one2one
    content =<<-'EOF'
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11    B1|B11
row2    A2|A22    B2|B22
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename, :persist => true)
    end

    res = {}
    tsv.traverse "ValueA", one2one: true do |k,v|
      res[k] = v
    end

    assert_include res["A2"][0], "row2"

  end

  def test_traverse_select
    content =<<-'EOF'
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11    B1|B11
row2    A2|A22    B2|B22
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :persist => true, select: "B1")

      assert_equal %w(row1), tsv.keys

      tsv = TSV.open(filename, :persist => true, select: "B2")

      assert_equal %w(row2), tsv.keys

      tsv = TSV.open(filename, :persist => true, select: "B1")

      assert_equal %w(row1), tsv.keys

      tsv = TSV.open(filename, :persist => true, select: "B2")

      assert_equal %w(row2), tsv.keys
    end
  end

  def test_traverse_named
    content =<<-EOF
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row3    a    C    Id4
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(File.open(filename), :sep => /\s+/)

      new_key, new_fields = tsv.through :key, ["ValueB"] do |key, values|
        assert_include %w(b B C), values["ValueB"].first
      end
    end
  end

  def test_traverse_change_key
    content =<<-EOF
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row3    a    C    Id4
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(File.open(filename), :sep => /\s+/)

      new_key, new_fields = tsv.through "ValueA" do |key, values|
        assert_include tsv.keys, values["Id"].first
      end

      assert_equal "ValueA", new_key
    end
  end

  def test_traverse_flat
    content =<<-EOF
#: :type=:flat
#Row   vA
row1    a    b    Id1
row2    A    B    Id3
row3    a    C    Id4
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :sep => /\s+/, :type => :flat)
      keys = []
      tsv.through "vA" do |k,v|
        keys << k
      end
      assert_include keys, "B"

      tsv.through :key do |k,v|
        assert_equal 3, v.length
      end

    end
  end

  def test_traverse_flat_same
    content =<<-EOF
#Id    ValueA
row1    a aa aaa
row2    A
row3    a
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(File.open(filename), :sep => /\s+/, :type => :flat)
      data = {}
      k, f = tsv.traverse "Id", ["ValueA"] do |k,v|
        data[k] = v
      end
      assert_equal %w(a aa aaa), data["row1"]
    end
  end

  def test_traverse_entity_list
    m = Module.new do
      extend Entity
      self.format = "ValueA"
    end

    content =<<-EOF
#Id    ValueA
row1    a
row2    A
row3    a
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(File.open(filename), :sep => /\s+/, :type => :list)
      data = {}
      k, f = tsv.traverse "Id", ["ValueA"] do |k,v|
        data[k] = v
      end
      assert_equal %w(a), data["row1"]
      assert Annotation::AnnotatedObject === data["row1"]
    end
  end

  def test_traverse_entity_double
    m = Module.new do
      extend Entity
      self.format = "ValueA"
    end

    content =<<-EOF
#Id    ValueA
row1    a|aa|aaa
row2    A
row3    a
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(File.open(filename), :sep => /\s+/)
      data = {}
      k, f = tsv.traverse "Id", ["ValueA"] do |k,v|
        data[k] = v
      end
      assert_equal %w(a aa aaa), data["row1"][0]
      assert NamedArray === data["row1"]
      assert AnnotatedArray === data["row1"]["ValueA"]
    end
  end


  def test_traverse_entity_flat
    m = Module.new do
      extend Entity
      self.format = "ValueA"
    end

    content =<<-EOF
#Id    ValueA
row1    a aa aaa
row2    A
row3    a
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(File.open(filename), :sep => /\s+/, :type => :flat)
      data = {}
      k, f = tsv.traverse "Id", ["ValueA"] do |k,v|
        data[k] = v
      end
      assert_equal %w(a aa aaa), data["row1"]
      assert AnnotatedArray === data["row1"]
      assert Annotation::AnnotatedObject === data["row1"][0]
    end
  end

  def test_traverse_entity_single
    m = Module.new do
      extend Entity
      self.format = "ValueA"
    end

    content =<<-EOF
#Id    ValueA
row1    a
row2    A
row3    a
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(File.open(filename), :sep => /\s+/, :type => :single)
      data = {}
      k, f = tsv.traverse "Id", ["ValueA"] do |k,v|
        data[k] = v
      end
      assert_equal "a", data["row1"]
      assert Annotation::AnnotatedObject === data["row1"]
    end
  end

  def test_tsv_traverse_select
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
    tsv.traverse "ValueA", :all, select: {ValueA: "A"} do |k,v|
      all_values.concat(v)
    end
    refute all_values.flatten.include? "row1"
    refute all_values.flatten.include? "a"
    refute all_values.flatten.include? "aaa"

    assert_include all_values.flatten, "row2"

    tsv.traverse "ValueA", :all, select: {ValueA: "a", invert: true} do |k,v|
      all_values.concat(v)
    end
    refute all_values.flatten.include? "row1"
    refute all_values.flatten.include? "a"
    refute all_values.flatten.include? "aaa"

    assert_include all_values.flatten, "row2"

    all_values = []
    tsv.traverse "Id", :all do |k,v|
      all_values.concat(v)
    end
    assert_include all_values.flatten, "row1"
    assert_include all_values.flatten, "a"
    assert_include all_values.flatten, "aaa"
  end

end

