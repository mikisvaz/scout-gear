require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')

require 'scout/tsv'

begin
  require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')
  class TestScoutTKRZW < Test::Unit::TestCase
    def test_open
      TmpFile.with_file nil do |tmp|
        db = ScoutTKRZW.open(tmp, true)
        1000.times do |i|
          db["foo#{i}"] = "bar#{i}"
        end
        assert_include db, 'foo1'
        assert_equal 1000, db.keys.length

        db.close
        TmpFile.with_file nil do |tmp_alt|
          Open.cp tmp, tmp_alt
          db2 = ScoutTKRZW.open(tmp_alt, false)
          assert_include db2, 'foo1'
          assert_equal 1000, db2.keys.length
        end
      end
    end

    def test_tkrzw
      content =<<-'EOF'
#: :sep=/\s+/#:type=:double#:merge=:concat
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    a    a    id3
      EOF

      tsv = TmpFile.with_file(content) do |filename|
        Persist.persist(__method__, 'tkh') do
          TSV.open(filename)
        end
      end


      assert_equal %w(a aa aaa), tsv["row1"][0]

      assert TSVAdapter === tsv
      assert TSV === tsv
      assert_include tsv.instance_variable_get(:@annotations), :key_field
      assert_include tsv.instance_variable_get(:@annotations), :serializer

      tsv.close
      tsv_loaded = assert_nothing_raised do
        TmpFile.with_file(content) do |filename|
          Persist.persist(__method__, 'tkh') do
            raise
          end
        end
      end

      assert_equal %w(a aa aaa), tsv_loaded["row1"][0]
    end

    def __test_benchmark1
      TmpFile.with_file nil do |tmp|

        Misc.benchmark(1000) do
          db = ScoutTKRZW.open(tmp, true)
          1000.times do |i|
            db["foo#{i}"] = "bar#{i}"
          end
          10.times do
            db.keys
          end
          10.times do |i|
            db["foo#{i}"]
          end
          Open.rm tmp
        end

        Misc.benchmark(1000) do
          db = ScoutCabinet.open(tmp, true)
          1000.times do |i|
            db["foo#{i}"] = "bar#{i}"
          end
          10.times do
            db.keys
          end
          10.times do |i|
            db["foo#{i}"]
          end
          db.close
          Open.rm tmp
        end
      end
    end

    def __test_benchmark2
      TmpFile.with_file nil do |tmp|

        db = ScoutTKRZW.open(tmp, true)
        10000.times do |i|
          db["foo#{i}"] = "bar#{i}"
        end

        Misc.benchmark(1000) do
          100.times do |i|
            db["foo#{i}"]
          end
        end

        Open.rm tmp
        db = ScoutCabinet.open(tmp, true)
        10000.times do |i|
          db["foo#{i}"] = "bar#{i}"
        end
        Misc.benchmark(1000) do
          100.times do |i|
            db["foo#{i}"]
          end
        end
      end
    end

  end
rescue Exception
end

