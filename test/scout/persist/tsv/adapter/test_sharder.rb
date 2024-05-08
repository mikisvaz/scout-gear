require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/persist/tsv'
class TestSharder < Test::Unit::TestCase
  def test_open_sharder
    TmpFile.with_file do |dir|
      shard_function = Proc.new do |key|
        key[-1]
      end

      size = 10
      sharder = Persist.open_sharder(dir, true, :HDB, :path => dir, :shard_function => shard_function, :persist => true, :serializer => :float_array)
      size.times do |v| 
        sharder[v.to_s] = [v, v*2]
      end
      assert_equal dir, sharder.persistence_path
      assert_equal size, sharder.size

      assert_equal [2,4], sharder["2"]
      count = 0
      sharder.each do |k,v|
        count += 1
      end
      assert_equal count, size

      TSV.setup(sharder, :key_field => "Letter", :fields => ["Value", "Value times 2"], :type => :list)

      assert_equal "Letter", sharder.key_field
      assert_equal [2,4], sharder["2"]
      assert_equal 2, sharder["2"]["Value"]

      sharder = Sharder.new dir, false do |key|
        key[-1]
      end

      sharder.extend ShardAdapter
      sharder.load_annotation_hash
      assert_equal size, sharder.keys.length
      assert_equal [2,4], sharder["2"]

      sharder = Persist.open_sharder dir do |key|
        key[-1]
      end

      assert_equal "Letter", sharder.key_field
      assert_equal [2,4], sharder["2"]
      assert_equal 2, sharder["2"]["Value"]
    end
  end

  def test_shard_tsv
    content =<<-EOF
#Id,ValueA,ValueB
id1,a1,b1
id2,a2,b2
id3,a3,b3
id11,a11,b11
    EOF

    TmpFile.with_file(content.gsub(',',"\t")) do |tsv_file|
      sharder = Persist.tsv(tsv_file, persist_options: { shard_function: proc{|k| k[-1] } }) do |data|
        TSV.open(tsv_file, data: data, type: :list)
      end
      assert_equal 'a1', sharder["id1"]["ValueA"]
    end
  end

  def test_shard_tsv_BDB
    content =<<-EOF
#Id,ValueA,ValueB
id1,a1,b1
id2,a2,b2
id3,a3,b3
id11,a11,b11
    EOF

    TmpFile.with_file(content.gsub(',',"\t")) do |tsv_file|
      sharder = Persist.tsv(tsv_file, engine: :BDB, persist_options: { shard_function: proc{|k| k[-1] } }) do |data|
        TSV.open(tsv_file, data: data, type: :list)
      end
      assert_equal 'a1', sharder["id1"]["ValueA"]
      assert_equal %w(id1 id11), sharder.prefix('id1')
    end
  end

  def test_shard_fwt
    TmpFile.with_file do |dir|
      shard_function = Proc.new do |key|
        key[0..(key.index(":")-1)]
      end

      pos_function = Proc.new do |key|
        key.split(":").last.to_i
      end

      size = 10
      sharder = Persist.tsv(dir,
                            persist_options: {
                              :engine => 'fwt', 
                              :path => dir, 
                              :serializer => :float,
                              :range => false, :value_size => 64, 
                              :shard_function => shard_function, 
                              :pos_function => pos_function
                            }
                           ) do |db|
                             size.times do |v| 
                               v = v + 1
                               chr = "chr" << (v % 5).to_s
                               key = chr + ":" << v.to_s
                               value = v*2
                               db[key] = value
                             end
                           end

      sharder.read

      assert_equal dir, sharder.persistence_path
      assert_equal size, sharder.size

      assert_equal 4.0, sharder["chr2:2"]

      count = 0
      sharder.through do |k,v|
        count += 1
      end
      assert_equal count, size

      sharder = Persist.open_sharder(dir, false, 'fwt', {:range => false, :value_size => 64, :pos_function => pos_function}, &shard_function)

      assert_equal 4.0, sharder["chr2:2"]

      assert_equal size, sharder.size 
    end
  end

  def test_shard_pki
    TmpFile.with_file do |dir|
      shard_function = Proc.new do |key|
        key[0..(key.index(":")-1)]
      end

      pos_function = Proc.new do |key|
        key.split(":").last.to_i
      end

      size = 10
      chrs = (1..10).to_a
      sharder = Persist.tsv(dir, 
                            engine: 'pki', 
                            :persist_options => { 
                              :pattern =>  %w(f f),
                              :range => false, 
                              :value_size => 64, 
                              :file => dir, 
                              :shard_function => shard_function,
                              :pos_function => pos_function
                            }) do |db|
        chrs.each do |c|
          size.times do |v| 
            v = v 
            chr = "chr" << c.to_s
            key = chr + ":" << v.to_s
            db[key] = [v, v*2]
          end
        end
      end
      sharder.read

      assert_equal dir, sharder.persistence_path

      db = sharder.database("chr2:2")
      db.read
      assert_equal [2.0, 4.0], sharder["chr2:2"]

      assert_equal size*chrs.length, sharder.size


      count = 0
      sharder.through do |k,v|
        count += 1
      end
      assert_equal count, size*chrs.length

      sharder = Persist.open_sharder(
        dir, false, 'pki', 
        {:pattern => %w(f f), :file => dir, :range => false, :value_size => 64, :pos_function => pos_function}, &shard_function
      )

      db = sharder.database("chr2:2")
      assert_equal [2.0, 4.0], sharder["chr2:2"]

      assert_equal size*chrs.length, sharder.size
    end
  end

  def test_shard_pki_skip
    TmpFile.with_file do |dir|
      shard_function = Proc.new do |key|
        key[0..(key.index(":")-1)]
      end

      pos_function = Proc.new do |key|
        key.split(":").last.to_i
      end

      size = 10
      chrs = (1..10).to_a
      sharder = Persist.tsv(dir, persist_options: {:pattern => %w(f), :range => false, :value_size => 64, :engine => 'pki', :file => dir, :shard_function => shard_function, :pos_function => pos_function}) do |db|
        chrs.each do |c|
          size.times do |v| 
            v = v + 1
            chr = "chr" << c.to_s
            key = chr + ":" << (v*2).to_s
            db[key] = [v*2]
          end
        end
      end
      sharder.read

      assert_equal dir, sharder.persistence_path

      assert_equal [2.0], sharder["chr2:2"]
      assert_equal [4.0], sharder["chr2:4"]

      count = 0
      sharder.through do |k,v|
        count += 1 unless v.nil?
      end
      assert_equal count, size*chrs.length

      sharder = Persist.open_sharder(dir, false, 'pki', {:range => false, :value_size => 64, :pos_function => pos_function}, &shard_function)

      assert_equal [2.0], sharder["chr2:2"]

    end
  end

  def test_shard_fwt_persist_tsv
    TmpFile.with_file do |dir|
      shard_function = Proc.new do |key|
        key[0..(key.index(":")-1)]
      end

      pos_function = Proc.new do |key|
        key.split(":").last.to_i
      end

      size = 10
      sharder = Persist.persist_tsv("ShardTSV_FWT", nil, {}, {
                              :engine => 'fwt', 
                              :path => dir, 
                              :serializer => :float,
                              :range => false, :value_size => 64, 
                              :shard_function => shard_function, 
                              :pos_function => pos_function
                            }
                           ) do |db|
                             size.times do |v| 
                               v = v + 1
                               chr = "chr" << (v % 5).to_s
                               key = chr + ":" << v.to_s
                               value = v*2
                               db[key] = value
                             end
                           end

      sharder.read

      assert_equal size, sharder.size

      assert_equal 4.0, sharder["chr2:2"]

      count = 0
      sharder.through do |k,v|
        count += 1
      end
      assert_equal count, size

      sharder = Persist.open_sharder(sharder.persistence_path, false, 'fwt', {:range => false, :value_size => 64, :pos_function => pos_function}, &shard_function)

      assert_equal 4.0, sharder["chr2:2"]

      assert_equal size, sharder.size 
    end
  end

end

