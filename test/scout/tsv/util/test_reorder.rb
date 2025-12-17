require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'

class TestReorder < Test::Unit::TestCase
  def test_reorder
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double
#Id    ValueA    ValueB    OtherID
row1    a1|a2    b1|b2    Id1|Id2
row2    A1|A3    B1|B3    Id1|Id3
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename)
    end

    r = tsv.reorder "OtherID", %w(ValueB Id)

    assert_equal %w(row1 row2), r["Id1"]["Id"]
    assert_equal %w(row2), r["Id3"]["Id"]
  end

  def test_reorder_list
    content =<<-'EOF'
#: :sep=/\s+/#:type=:list
#Id    ValueA    ValueB    OtherID
row1    a1    b1    Id1
row2    A1    B1    Id1
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename)
    end

    r = tsv.reorder "ValueB"

    assert_equal "row1", r["b1"]["Id"]
    assert_equal "row2", r["B1"]["Id"]
  end

  def test_reorder_single
    content =<<-'EOF'
#: :sep=/\s+/#:type=:single
#Id    ValueA
row1    a1
row2    A1
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename)
    end

    r = tsv.reorder "ValueA"

    assert_equal "row1", r["a1"]
    assert_equal "row2", r["A1"]
  end

  def test_reorder_single_to_double
    content =<<-'EOF'
#: :sep=/\s+/#:type=:single
#Id    ValueA
row1    a1
row2    a1
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      TSV.open(filename)
    end

    r = tsv.reorder "ValueA", type: :flat

    assert_equal ["row1", "row2"], r["a1"]
  end

  def test_transpose
     content =<<-EOF
#: :type=:list
#Row   vA   vB   vID
row1    a    b    Id1
row2    A    B    Id3
row3    a    C    Id4
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :sep => /\s+/)

      assert_equal %w(vA vB vID),  tsv.transpose("Values").keys
      assert_equal %w(Id1 Id3 Id4),  tsv.transpose("Values")["vID"]
    end
  end

  def test_column
    content =<<-EOF
#Id    ValueA    ValueB ValueC
rowA    A|AA    B|BB  C|CC
rowa    a|aa    b|BB  C|CC
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(File.open(filename), :sep => /\s+/, :type => :double)
      tsv = tsv.column("ValueA", cast: :downcase)
      assert_equal %w(a aa), tsv["rowA"]
      assert_equal %w(a aa), tsv["rowa"]
    end
  end

  def test_slice_empty
    content =<<-EOF
#ID ValueA ValueB Comment
row1 a b c
row2 A B C
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(File.open(filename), :type => :list, :sep => /\s/)
      tsv = tsv.slice []
      assert tsv.fields.empty?
      TmpFile.with_file do |tmpfile|
        Open.write(tmpfile, tsv.to_s)
        tsv = TSV.open tmpfile
        assert tsv.fields.empty?
      end
    end
  end

  def test_reorder_flat
    content =<<-EOF
#Id    ValueA
row1    a aa aaa
row2    A
row3    a
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(File.open(filename), :sep => /\s+/, :type => :flat)

      assert_equal ["row1", "row3"].sort, tsv.reorder("ValueA")["a"]
    end
  end

  def test_reorder_flat_same
    content =<<-EOF
#Id    ValueA
row1    a aa aaa
row2    A
row3    a
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(File.open(filename), :sep => /\s+/, :type => :flat)

      reordered = tsv.reorder("Id", ["ValueA"])
      assert_equal %w(ValueA), reordered.fields
      assert_equal ["a", "aa", "aaa"].sort, reordered["row1"]
    end
  end
end

