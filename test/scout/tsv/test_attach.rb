require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'

class TestTSVAttach < Test::Unit::TestCase
  def test_attach_simple
    content1 =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    a|aa|aaa    b
row2    A    B
    EOF

    content2 =<<-EOF
#: :sep=" "
#ID    ValueB    OtherID
row1    b    Id1|Id2
row3    B    Id3
    EOF

    TmpFile.with_file(content1) do |filename1|
      TmpFile.with_file(content2) do |filename2|
        tsv = TSV.open(filename1)
        other = TSV.open(filename2)
        tsv.attach other, :complete => true
        assert_equal %w(Id1 Id2), tsv["row1"]["OtherID"]
        assert_equal %w(Id3), tsv["row3"]["OtherID"]
        assert_equal %w(B), tsv["row3"]["ValueB"]
      end
    end
  end

  def test_attach_by_key
    content1 =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11    B1|B11
row2    A2|A22    B2|B22
    EOF

    content2 =<<-EOF
#: :sep=" "
#ID    ValueB    OtherID
row1    B1|B11    Id1|Id11
row2.2    B2|B22|B222    Id2.2|Id22.2|Id222.2
row3    B3    Id3
    EOF

    TmpFile.with_file(content1) do |filename1|
      TmpFile.with_file(content2) do |filename2|
        tsv = TSV.open(filename1)
        other = TSV.open(filename2)
        tsv.attach other, complete: true, match_key: "ValueB"
        assert_equal %w(A1 A11), tsv["row1"]["ValueA"]
        assert_equal %w(B1 B11), tsv["row1"]["ValueB"]
        assert_equal %w(Id1 Id11), tsv["row1"]["OtherID"]
        assert_equal %w(Id2.2 Id22.2), tsv["row2"]["OtherID"]
      end
    end
  end

  def test_attach_by_reorder
    content1 =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    A1|A11    B1|B11
row2    A2|A22    B2|B22
    EOF

    content2 =<<-EOF
#: :sep=" "
#ValueB ID  OtherID
B1  row1|row1.1  Id1|Id11
B2 row2    Id2.2|Id22.2|Id222.2
B3 row3   Id3
    EOF

    TmpFile.with_file(content1) do |filename1|
      TmpFile.with_file(content2) do |filename2|
        tsv = TSV.open(filename1)
        other = TSV.open(filename2)
        tsv.attach other, match_key: "ID", one2one: false
        assert_equal %w(A1 A11), tsv["row1"]["ValueA"]
        assert_equal %w(B1 B11), tsv["row1"]["ValueB"]
        assert_equal %w(Id1 Id11), tsv["row1"]["OtherID"]
        assert_equal %w(Id2.2 Id22.2 Id222.2), tsv["row2"]["OtherID"]
      end
    end
  end


  def test_attach_same_key
    content1 =<<-EOF
#ID    ValueA    ValueB
row1    a|aa|aaa    b
row2    A    B
    EOF

    content2 =<<-EOF
#ID    ValueB    OtherID
row1    b    Id1|Id2
row3    B    Id3
    EOF

    tsv1 = tsv2 = nil
    TmpFile.with_file(content1) do |filename|
      tsv1 = TSV.open(File.open(filename), type: :double, :sep => /\s+/)
    end

    TmpFile.with_file(content2) do |filename|
      tsv2 = TSV.open(File.open(filename), type: :double, :sep => /\s+/)
    end

    tsv1.attach tsv2, fields: "OtherID"

    assert_equal %w(ValueA ValueB OtherID), tsv1.fields
    assert_equal %w(Id1 Id2), tsv1["row1"]["OtherID"]

    TmpFile.with_file(content1) do |filename|
      tsv1 = TSV.open(File.open(filename), type: :double, :sep => /\s+/)
    end

    tsv1.attach tsv2

    assert_equal %w(ValueA ValueB OtherID), tsv1.fields

    tsv1 = tsv2 = nil
    TmpFile.with_file(content1) do |filename|
      tsv1 = TSV.open(File.open(filename), type: :list, :sep => /\s+/)
    end

    TmpFile.with_file(content2) do |filename|
      tsv2 = TSV.open(File.open(filename), type: :double, :sep => /\s+/)
    end

    tsv1.attach tsv2, fields: "OtherID"

    assert_equal %w(ValueA ValueB OtherID), tsv1.fields
    assert_equal "Id1", tsv1["row1"]["OtherID"]
  end

  def test_attach_source_field
    content1 =<<-EOF
#Id    ValueA    ValueB
row1    a|aa|aaa    b
row2    A    B
    EOF

    content2 =<<-EOF
#ValueB    OtherID
b    Id1|Id2
B    Id3
    EOF

    tsv1 = tsv2 = nil
    TmpFile.with_file(content1) do |filename|
      tsv1 = TSV.open(File.open(filename), type: :double, :sep => /\s+/)
    end

    TmpFile.with_file(content2) do |filename|
      tsv2 = TSV.open(File.open(filename), type: :double, :sep => /\s+/)
    end

    tsv1.attach tsv2, bar: true

    assert_equal %w(ValueA ValueB OtherID), tsv1.fields
    assert_equal %w(Id1 Id2), tsv1["row1"]["OtherID"]

    TmpFile.with_file(content1) do |filename|
      tsv1 = TSV.open(File.open(filename), type: :list, :sep => /\s+/)
    end

    tsv1.attach tsv2

    assert_equal %w(ValueA ValueB OtherID), tsv1.fields
    assert_equal "Id1", tsv1["row1"]["OtherID"]
  end

  def test_attach_transformer
    content1 =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    a|aa|aaa    b
row2    A    B
    EOF

    content2 =<<-EOF
#: :sep=" "
#ID    ValueB    OtherID
row1    b    Id1|Id2
row3    B    Id3
    EOF

    TmpFile.with_file(content1) do |filename1|
      TmpFile.with_file(content2) do |filename2|
        out = TSV.attach filename1, filename2, target: :stream, bar: false
        tsv = out.tsv
        assert_equal %w(Id1 Id2), tsv["row1"]["OtherID"]
      end
    end
  end

  def test_attach_flexible_names
    content1 =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    a|aa|aaa    b
row2    A    B
    EOF

    content2 =<<-EOF
#: :sep=" "
#Identifiers(ID) OtherID
row1        Id1|Id2
row3        Id3
    EOF

    TmpFile.with_file(content1) do |filename1|
      TmpFile.with_file(content2) do |filename2|
        out = TSV.attach filename1, filename2, target: :stream, bar: false
        tsv = out.tsv
        assert_equal %w(Id1 Id2), tsv["row1"]["OtherID"]
      end
    end
  end
end
