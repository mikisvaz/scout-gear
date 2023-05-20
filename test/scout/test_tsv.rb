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
      tsv = TSV.open(filename, :persist => true)
      tsv.close
      Persist::CONNECTIONS.clear
      TSV.open(filename, :persist => true)
    end

    assert_equal "Id", tsv.key_field

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

  def test_headerless_fields
    content =<<-EOF
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :sep => /\s+/, :fields => [1])
      assert_equal ["a", "aa", "aaa"], tsv["row1"][0]
      assert_equal :double, tsv.type
      assert_equal [%w(a aa aaa)], tsv["row1"]
    end
  end

  def test_tsv_field_selection
    content =<<-EOF
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :sep => /\s+/, :type => :single)
      assert_equal ["ValueA"], tsv.fields
    end
  end

  def test_tsv_single_from_flat
    content =<<-EOF
#: :type=:flat
#Id    Value
row1    1 2
row2    4
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :sep => /\s+/, :type => :single, :key_field => "Value", :fields => ["Id"])
      assert_equal "row1", tsv["1"]
    end
  end

  def test_key_field
    content =<<-EOF
#: :sep=/\\s+/#:type=:single
#Id Value
a 1
b 2
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :key_field => "Value")
      assert_equal %w(Id), tsv.fields
      assert_equal "Value", tsv.key_field
      assert_equal "a", tsv["1"]
    end
  end

  def test_fix
    content =<<-EOF
#: :sep=/\\s+/#:type=:single
#Id Value
a 1
b 2
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :key_field => "Value", :fix => Proc.new{|l| if l =~ /1/;then "a 3" else l end})
      assert_equal "a", tsv["3"]
    end
  end

  def test_flat
    content =<<-EOF
#: :type=:flat
#Id    Value
row1    a|aa|aaa
row2    A|AA|AAA
    EOF

    TmpFile.with_file(content) do |filename|
      assert TSV.open(filename, :sep => /\s+/, :type => :flat).include? "row1"
      assert TSV.open(filename, :sep => /\s+/, :type => :flat)["row1"].include? "a"
      assert TSV.open(filename, :sep => /\s+/, :type => :flat, :key_field => "Id")["row1"].include? "a"
      assert TSV.open(filename, :sep => /\s+/, :type => :flat, :key_field => "Id", :fields => ["Value"])["row1"].include? "a"
    end
  end

  def test_tsv_flat_double
    content =<<-EOF
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :sep => /\s+/, :type => :flat, :key_field => "ValueA", :fields => ["OtherID"], :merge => true)
      assert tsv["aaa"].include? "Id1"
      assert tsv["aaa"].include? "Id2"
    end
  end

  def test_flat2single
    content =<<-EOF
#: :type=:flat
#Id    Value
row1    a aa aaa
row2    A AA AAA
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :sep => /\s+/, :type => :single, :key_field => "Value")
      assert tsv.include? "aaa"
    end
  end

  def test_flat_key
    content =<<-EOF
#Id    ValueA 
row1   a   aa   aaa
row2   b  bbb bbbb bb aa
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :sep => /\s+/, :merge => true, :type => :flat, :key_field => "ValueA")
      assert_equal ["row1"], tsv["a"]
      assert_equal ["row1", "row2"], tsv["aa"]
    end
  end

  def test_unnamed_key
    content =<<-EOF
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :sep => /\s+/, :key_field => 1)
      assert tsv.keys.include? "a"
    end
  end

  def test_grep
    content =<<-EOF
#: :sep=/\\s+/#:type=:single
#Id Value
a 1
b 2
c 3
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :key_field => "Value", :grep => "#\\|2")
      assert_includes tsv, "2"
      refute_includes tsv, "3"
    end
  end

  def TODO_test_tsv_grep
    content =<<-EOF
#: :sep=/\\s+/#:type=:single
#Id Value
a 1
b 2
b 3
d 22
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :key_field => "Value", :tsv_grep => "2")
      assert_includes tsv, "2"
      refute_includes tsv, "3"
      assert(tsv.include?("2"))
      assert(! tsv.include?("3"))
    end
  end

  def test_flat_with_field_header
    content =<<-EOF
#: :type=:flat
#Id    ValueA
row1   a   aa   aaa
row2   b  bbb bbbb bb
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :sep => /\s+/, :merge => false)
      assert_equal ["a", "aa", "aaa"], tsv["row1"]
    end
  end

  def test_alt_args
    content =<<-EOF
#Id    ValueA
row1   a   aa   aaa
row2   b  bbb bbbb bb
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, type: :flat, :sep => /\s+/, :merge => false)
      assert_equal ["a", "aa", "aaa"], tsv["row1"]
    end

    tsv = TSV.str_setup("ID~ValueA,ValueB#:type=:flat", {})
    assert_equal "ID", tsv.key_field
  end
end
