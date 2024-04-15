require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'

class TestTSVTokyo < Test::Unit::TestCase
  def test_tokyo
    content =<<-'EOF'
#: :sep=/\s+/#:type=:double#:merge=:concat
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    a    a    id3
    EOF

    tsv = TmpFile.with_file(content) do |filename|
      Persist.persist(__method__, :HDB) do
        TSV.open(filename)
      end
    end

    assert_equal %w(a aa aaa), tsv["row1"][0]

    assert TSVAdapter === tsv
    assert TSV === tsv
    assert_include tsv.instance_variable_get(:@annotations), :key_field
    assert_include tsv.instance_variable_get(:@annotations), :serializer

    tsv_loaded = assert_nothing_raised do
      TmpFile.with_file(content) do |filename|
        Persist.persist(__method__, :HDB) do
          raise
        end
      end
    end


    assert_equal %w(a aa aaa), tsv_loaded["row1"][0]
  end

  def test_custom_load
    tsv = TSV.setup({}, :type => :double, :key_field => "Key", :fields => %w(Field1 Field2))

    size = 100_000
    (0..size).each do |i|
      k = "key-#{i}"
      values1 = 3.times.collect{|j| "value-#{i}-1-#{j}" }
      values2 = 5.times.collect{|j| "value-#{i}-2-#{j}" }

      tsv[k] = [values1, values2]
    end

    tc = Persist.persist(__method__, :HDB) do |file|
      tsv
    end

    100.times do
      i = rand(size).floor
      assert_equal tc["key-#{i}"], tsv["key-#{i}"]
    end
  end

  def __test_benchmark
    tsv = TSV.setup({}, :type => :double, :key_field => "Key", :fields => %w(Field1 Field2))

    size = 100_000
    (0..size).each do |i|
      k = "key-#{i}"
      values1 = 3.times.collect{|j| "value-#{i}-1-#{j}" }
      values2 = 5.times.collect{|j| "value-#{i}-2-#{j}" }

      tsv[k] = [values1, values2]
    end

    tc = Persist.persist(__method__, :HDB) do |file|
      data = ScoutCabinet.open(file, true, "HDB")
      TSV.setup(data, :type => :double, :key_field => "Key", :fields => %w(Field1 Field2))
      data.extend TSVAdapter
      Log::ProgressBar.with_bar size do |b|
        (0..size).each do |i|
          b.tick
          k = "key-#{i}"
          values1 = 3.times.collect{|j| "value-#{i}-1-#{j}" }
          values2 = 5.times.collect{|j| "value-#{i}-2-#{j}" }

          data[k] = [values1, values2]
        end
      end
      data
    end

    100.times do
      i = rand(size).floor
      assert_equal tc["key-#{i}"], tsv["key-#{i}"]
    end
  end

  def test_float_array
    content =<<-EOF
#Id    ValueA    ValueB    OtherID
row1   0.2   0.3 0
row2    0.1  4.5 0
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :sep => /\s+/, :persist => true, :type => :list, :cast => :to_f, :persist_update => true)
      assert_equal [0.2, 0.3, 0], tsv["row1"]
      assert_equal TSVAdapter::FloatArraySerializer, tsv.serializer
      Open.cp tsv.persistence_path, tmpdir.persistence.foo
      tsv2 = ScoutCabinet.open(tmpdir.persistence.foo, false)
      tsv2.extend TSVAdapter
      assert_equal [0.2, 0.3, 0], tsv2["row1"]
      assert_equal TSVAdapter::FloatArraySerializer, tsv2.serializer
    end
 
  end

  def test_float_double
    content =<<-EOF
#Id    ValueA    ValueB    OtherID
row1   0.2   0.3 0
row2    0.1  4.5 0
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(filename, :sep => /\s+/, :persist => true, :type => :double, :cast => :to_f)
      assert_equal Marshal, tsv.serializer
      assert_equal [[0.2], [0.3], [0.0]], tsv["row1"]
      tsv.close

      Persist::CONNECTIONS.clear

      tsv = TSV.open(filename, :sep => /\s+/, :persist => true, :type => :double, :cast => :to_f)
      assert_equal Marshal, tsv.serializer
      assert_equal [[0.2], [0.3], [0.0]], tsv["row1"]
    end
  end

  def test_importsv_list
    content =<<-EOF
#Id    ValueA    ValueB    OtherID
row1   0.2   0.3 0
row2    0.1  4.5 0
    EOF

    TmpFile.with_path(content.gsub(/ +/,"\t")) do |filename|
      TmpFile.with_file do |persistence_path|
        parser = TSV::Parser.new filename, type: :list
        database = ScoutCabinet.open persistence_path, true, :HDB
        parser.with_stream do |stream|
          ScoutCabinet.importtsv(database, stream)
        end
        database.write_and_read do
          TSV.setup(database, **parser.options)
          database.extend TSVAdapter
        end

        assert_equal '0.2', database["row1"]["ValueA"]
      end
    end
  end

  def test_importsv_double
    content =<<-EOF
#Id    ValueA    ValueB    OtherID
row1   a|aa   b|bb    c|cc
row2   A|AA   B|BB   C|CC
    EOF

    TmpFile.with_path(content.gsub(/ +/,"\t")) do |filename|
      TmpFile.with_file do |persistence_path|
        parser = TSV::Parser.new filename, type: :double
        database = ScoutCabinet.open persistence_path, true, :HDB
        parser.with_stream do |stream|
          ScoutCabinet.importtsv(database, stream)
        end
        database.write_and_read do
          TSV.setup(database, **parser.options)
          database.extend TSVAdapter
        end

        assert_equal %w(A AA), database["row2"]["ValueA"]
      end
    end
  end

  def test_importsv_large
    content =<<-EOF.gsub(/ +/, "\t")
#Id    ValueA    ValueB
    EOF

    10_000.times do |i|
      content += "row#{i}\ta#{i}\tb#{i}\n"
    end

    TmpFile.with_path(content) do |filename|
      TmpFile.with_file do |persistence_path|
        parser = TSV::Parser.new filename, type: :list
        database = ScoutCabinet.open persistence_path, true, :HDB
        parser.with_stream do |stream|
          ScoutCabinet.importtsv(database, stream)
        end
        database.write_and_read do
          TSV.setup(database, **parser.options)
          database.extend TSVAdapter
        end

        assert_equal "a1000", database["row1000"]["ValueA"]
      end
    end
  end

  def test_importsv_double_BDB
    content =<<-EOF
#Id    ValueA    ValueB    OtherID
row1   a|aa   b|bb    c|cc
row2   A|AA   B|BB   C|CC
    EOF

    TmpFile.with_path(content.gsub(/ +/,"\t")) do |filename|
      TmpFile.with_file do |persistence_path|
        parser = TSV::Parser.new filename, type: :double
        database = ScoutCabinet.open persistence_path, true, :BDB
        parser.with_stream do |stream|
          ScoutCabinet.importtsv(database, stream)
        end
        database.write_and_read do
          TSV.setup(database, **parser.options)
          database.extend TSVAdapter
        end

        assert_equal %w(A AA), database["row2"]["ValueA"]
        assert_equal %w(row1 row2), database.prefix("row")
      end
    end
  end

  def test_importsv_from_file
    content =<<-EOF
#Id    ValueA    ValueB    OtherID
row1   a|aa   b|bb    c|cc
row2   A|AA   B|BB   C|CC
    EOF

    TmpFile.with_path(content.gsub(/ +/,"\t")) do |filename|
      TmpFile.with_file do |persistence_path|
        parser = TSV::Parser.new filename, type: :double
        database = ScoutCabinet.open persistence_path, true, :HDB
        parser.with_stream do |stream|
          database.load_stream stream
        end
        database.write_and_read do
          TSV.setup(database, **parser.options)
          database.extend TSVAdapter
        end

        assert_equal %w(A AA), database["row2"]["ValueA"]
      end
    end
  end

end

