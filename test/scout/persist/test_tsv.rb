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

    assert NamedArray === tsv["row1"]

    assert_include tsv.keys, 'row1'
    assert_include tsv.keys, 'row2'

    tsv = Persist.persist("TEST Persist TSV", :tsv) do 
      TmpFile.with_file(content) do |filename|
        TSV.open(filename)
      end
    end

    assert_include tsv.keys, 'row1'
    assert_include tsv.keys, 'row2'

    assert_nothing_raised do
      tsv = Persist.persist("TEST Persist TSV", :tsv) do 
        raise
      end
    end

    assert_include tsv.fields, "ValueA"
    assert_include tsv.keys, 'row1'
    assert_include tsv.keys, 'row2'
  end

  def test_persist_with_data
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double#:merge=:concat
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    a    a    id3
    EOF


    tsv = nil
    TmpFile.with_file do |tk|
      data = Persist.open_tokyocabinet(tk, true, "HDB")
      assert Open.exists?(tk)
      tsv = Persist.persist("TEST Persist TSV", :HDB, :persist_data => data) do |data|
        t = TmpFile.with_file(content) do |filename|
          TSV.open(filename, persist_data: data)
        end
        t
        nil
      end
      refute Open.exists?(tk)
      assert Open.exists?(data.persistence_path)
      refute tsv.fields.nil?
    end

    assert_include tsv.keys, 'row1'
    assert_include tsv.keys, 'row2'

    assert_nothing_raised do
      tsv = Persist.persist("TEST Persist TSV", :HDB) do 
        raise
      end
    end

    assert_include tsv.keys, 'row1'
    assert_include tsv.keys, 'row2'
  end

  def test_tsv
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double#:merge=:concat
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    a    a    id3
    EOF


    tsv = nil
    TmpFile.with_file(content) do |filename|
      tsv = Persist.tsv("Some TSV") do |data|
        TSV.open(filename, persist_data: data)
      end
      assert_equal ['b'], tsv["row1"][1]
      assert NamedArray === tsv["row1"]
      assert_equal ['b'], tsv["row1"]["ValueB"]
      assert_include tsv.keys, 'row1'
      assert_include tsv.keys, 'row2'
      assert_nothing_raised do
        tsv = Persist.tsv("Some TSV") do |data|
          raise
        end
      end
    end

    assert_include tsv.keys, 'row1'
    assert_include tsv.keys, 'row2'
  end

  def test_persist_tsv
    content =<<-'EOF'
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    a    a    id3
    EOF


    tsv = nil
    TmpFile.with_file(content) do |filename|
      tsv = Persist.persist_tsv("Some TSV", sep: /\s+/, type: :double) do |data|
        TSV.open(filename, sep: /\s+/, type: :double, persist_data: data)
      end
      assert_equal ['b'], tsv["row1"][1]
      assert NamedArray === tsv["row1"]
      assert_equal ['b'], tsv["row1"]["ValueB"]
      assert_include tsv.keys, 'row1'
      assert_include tsv.keys, 'row2'
      assert_nothing_raised do
        tsv = Persist.persist_tsv("Some TSV", sep: /\s+/, type: :double) do |data|
          raise
        end
      end
    end

    assert_include tsv.keys, 'row1'
    assert_include tsv.keys, 'row2'
  end

  def test_tsv_open_persist
    content =<<-'EOF'
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    a    a    id3
    EOF


    tsv = nil
    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, sep: /\s+/, type: :double, persist: true, merge: true)
      assert Array === tsv.fields
      tsv = TSV.open(filename, sep: /\s+/, type: :double, persist: true, merge: true)
      assert Array === tsv.fields
    end
  end
end

