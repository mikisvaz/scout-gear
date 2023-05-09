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

  def test_speed
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
end

