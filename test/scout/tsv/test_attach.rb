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

  def test_attach_single
    content1 =<<-EOF
#: :sep=","
#ID,ValueA
row1,a
row2,A
    EOF

    content2 =<<-EOF
#: :sep=","
#ID,ValueB
row1,b
row3,B
    EOF

    TmpFile.with_file(content1) do |filename1|
      TmpFile.with_file(content2) do |filename2|
        tsv = TSV.open(filename1, type: :single)
        other = TSV.open(filename2, type: :single)
        tsv = tsv.attach other, :complete => true
        assert_equal 'b', tsv["row1"]["ValueB"]
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

    tsv1 = tsv1.attach tsv2, bar: true

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

  def test_attach_index
    content1 =<<-EOF
#Id    ValueA    ValueB
row1    a|aa|aaa    b
row2    A    B
    EOF

    content2 =<<-EOF
#ValueE    OtherID
e    Id1|Id2
E    Id3
    EOF

    content_index =<<-EOF
#Id    ValueE
row1    e
row2    E
    EOF

    tsv1 = tsv2 = index = nil
    TmpFile.with_file(content1) do |filename|
      tsv1 = TSV.open(File.open(filename), type: :double, :sep => /\s+/)
    end

    TmpFile.with_file(content2) do |filename|
      tsv2 = TSV.open(File.open(filename), type: :double, :sep => /\s+/)
    end

    TmpFile.with_file(content_index) do |filename|
      index = TSV.open(File.open(filename), type: :flat, :sep => /\s+/)
    end

    tsv1.attach tsv2, index: index

    assert_equal %w(ValueA ValueB OtherID), tsv1.fields
    assert_equal %w(Id1 Id2), tsv1["row1"]["OtherID"]

    TmpFile.with_file(content1) do |filename|
      tsv1 = TSV.open(File.open(filename), type: :list, :sep => /\s+/)
    end

    tsv1.attach tsv2, index: index

    assert_equal %w(ValueA ValueB OtherID), tsv1.fields
    assert_equal "Id1", tsv1["row1"]["OtherID"]
  end

  def test_attach_complete_identifiers
    content1 =<<-EOF
#: :sep=/\\s+/
#Id    ValueA
row1    a|aa|aaa
row2    A
    EOF

    content2 =<<-EOF
#: :sep=/\\s+/
#Id2    ValueB
ROW_1    b
ROW_2    C
    EOF

    identifiers =<<-EOF
#: :sep=/\\s+/
#Id    Id2
row1    ROW_1
row2    ROW_2
row3    ROW_3
    EOF
    Scout.claim Scout.tmp.test_tmpdir.test1.data, :string, content1
    Scout.claim Scout.tmp.test_tmpdir.test2.data, :string, content2
    Scout.claim Scout.tmp.test_tmpdir.identifiers.data, :string, identifiers

    tsv1 = tsv2 = nil

    tsv1 = Scout.tmp.test_tmpdir.test1.data.produce(true).tsv type: :double,  :sep => /\s+/
    tsv2 = Scout.tmp.test_tmpdir.test2.data.produce(true).tsv type: :double,  :sep => /\s+/
    ids = Scout.tmp.test_tmpdir.identifiers.data.produce(true).tsv type: :double,  :sep => /\s+/

    tsv1.identifiers = ids

    tsv1 = tsv1.attach tsv2

    assert_equal [["A"], ["C"]], tsv1["row2"]

    tsv1 = Scout.tmp.test_tmpdir.test1.data.produce(true).tsv type: :double,  :sep => /\s+/
    tsv2 = Scout.tmp.test_tmpdir.test2.data.produce(true).tsv type: :double,  :sep => /\s+/
    ids = Scout.tmp.test_tmpdir.identifiers.data.produce(true).tsv  type: :double,  :sep => /\s+/

    tsv1.identifiers = ids

    tsv1 = tsv1.attach tsv2, :complete => true
    assert_equal [["A"], ["C"]], tsv1["row2"]
  end

  def test_attach_index_both_non_key
    content1 =<<-EOF
#: :sep=/\\s+/
#Id    ValueA    ValueB
row1    a|aa|aaa    b
row2    A    B
    EOF

    content2 =<<-EOF
#: :sep=/\\s+/
#ValueE    OtherID
e    Id1|Id2
E    Id3
    EOF

    content_index =<<-EOF
#: :sep=/\\s+/
#ValueA    OtherID
a    Id1
A    Id3
    EOF

    tmpdir = Scout.tmp.test_tmp

    Scout.claim tmpdir.test1.data, :string, content1
    Scout.claim tmpdir.test2.data, :string, content2
    Scout.claim tmpdir.test2.identifiers, :string, content_index

    tsv1 = tsv2 = nil

    tsv1 = tmpdir.test1.data.produce(true).tsv type: :double,  :sep => /\s+/
    tsv2 = tmpdir.test2.data.produce(true).tsv type: :double,  :sep => /\s+/

    tsv2.identifiers = tmpdir.test2.identifiers.produce(true).produce.find #.to_s

    tsv1.attach tsv2, :fields => ["ValueE"] #, :persist_input => true
    assert_equal [["a", "aa", "aaa"], ["b"], ["e"]], tsv1["row1"]
  end

  def test_attach_single_nils
    content1 =<<-EOF
#Id,ValueA
row1,
row2,AA
    EOF
    content2 =<<-EOF
#Id,ValueB
row1,B
row2,BB
    EOF
    content3 =<<-EOF
#Id,ValueC
row1,
row2,CC
    EOF

    tsv1 = tsv2 = tsv3 = tsv4 = index = nil
    TmpFile.with_file(content1) do |filename|
      tsv1 = TSV.open(File.open(filename), :sep => ',', :type => :single)
      tsv1.keys.each{|k| tsv1[k] = nil if tsv1[k] == ""}
    end

    TmpFile.with_file(content2) do |filename|
      tsv2 = TSV.open(File.open(filename), :sep => ',', :type => :single)
      tsv2.keys.each{|k| tsv2[k] = nil if tsv2[k] == ""}
    end

    TmpFile.with_file(content3) do |filename|
      tsv3 = TSV.open(File.open(filename), :sep => ',', :type => :single)
      tsv3.keys.each{|k| tsv3[k] = nil if tsv3[k] == ""}
    end

    tmp = tsv1.attach(tsv2, :complete => true)
    tmp = tmp.attach(tsv3, :complete => true)
    assert_equal [nil, "B", nil], tsv1.attach(tsv2, :complete => true).attach(tsv3, :complete => true)["row1"]
    assert_equal [nil, "B", nil], tsv1.attach(tsv2, :complete => true).attach(tsv3, :complete => true)["row1"]
  end

  def test_attach_flat
    content1 =<<-EOF
#Id    ValueA    ValueB
row1    a|aa|aaa    b
row2    A    B
    EOF

    content2 =<<-EOF
#ValueA    OtherID
a    Id1|Id2
A    Id3
    EOF

    tsv1 = tsv2 = index = nil
    TmpFile.with_file(content1) do |filename|
      tsv1 = TSV.open(File.open(filename), type: :flat, fields: ["ValueA"], sep: /\s+/)
    end

    TmpFile.with_file(content2) do |filename|
      tsv2 = TSV.open(File.open(filename), type: :double, sep: /\s+/)
    end

    res = tsv1.attach tsv2, :fields => ["OtherID"]
    assert res["row2"].include? "Id3"
    assert ! res["row2"].include?("b")
  end
end
