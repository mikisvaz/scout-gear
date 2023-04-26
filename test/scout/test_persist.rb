require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestPersist < Test::Unit::TestCase
  def test_string
    TmpFile.with_file do |tmpfile|
      Path.setup(tmpfile)
      obj = "TEST"
      type = :string
      refute tmpdir.persist.glob("*").any?
      assert_equal obj, Persist.persist(tmpfile, type, :dir => tmpdir.persist){ obj }
      assert tmpdir.persist.glob("*").any?
      assert_equal obj, Persist.persist(tmpfile, type, :dir => tmpdir.persist){ raise "Error" }
    end
  end

  def test_float_array
    TmpFile.with_file do |tmpfile|
      Path.setup(tmpfile)
      obj = [1.2,2.2]
      type = :float_array
      refute tmpdir.persist.glob("*").any?
      assert_equal obj, Persist.persist(tmpfile, type, :dir => tmpdir.persist){ obj }
      assert tmpdir.persist.glob("*").any?
      assert_equal obj, Persist.persist(tmpfile, type, :dir => tmpdir.persist){ raise "Error" }
    end
  end

  def test_string_update
    TmpFile.with_file do |tmpfile|
      Path.setup(tmpfile)
      obj = "TEST"
      type = :string
      refute tmpdir.persist.glob("*").any?
      assert_equal obj, Persist.persist(tmpfile, type, :dir => tmpdir.persist){ obj }
      assert tmpdir.persist.glob("*").any?
      assert_raises ScoutException do 
        Persist.persist(tmpfile, type, :dir => tmpdir.persist, :update => true){ raise ScoutException }
      end
      assert_raises ScoutException do 
        Persist.persist(tmpfile, type, :persist_dir => tmpdir.persist, :persist_update => true){ raise ScoutException }
      end
    end
  end

  def test_stream
    TmpFile.with_file do |tmpfile|
      Path.setup(tmpfile)
      obj = "TEST\nTEST"
      stream = StringIO.new obj
      stream.rewind
      res = Persist.persist(tmpfile, :string, :dir => tmpdir.persist){ stream }
      assert IO === res
      assert_equal obj, res.read
      assert_equal obj, Persist.persist(tmpfile, :string, :dir => tmpdir.persist){ raise ScoutException }
    end
  end

  def test_update_time
    TmpFile.with_file do |dir|
      Path.setup(dir)
      obj = "TEST"
      type = :string

      Open.write(dir.file, "TEST")
      assert_equal "TEST", Persist.persist(dir.cache, type, :dir => tmpdir.persist){ Open.read(dir.file) }
      Open.rm(dir.file)
      assert_equal "TEST", Persist.persist(dir.cache, type, :dir => tmpdir.persist){ Open.read(dir.file) }

      sleep 1
      Open.write(dir.file2, "TEST2")
      assert_equal "TEST", Persist.persist(dir.cache, type, :dir => tmpdir.persist){ Open.read(dir.file2) }
      assert_equal "TEST2", Persist.persist(dir.cache, type, :dir => tmpdir.persist, :update => dir.file2){ Open.read(dir.file2) }

      sleep 1
      Open.write(dir.file3, "TEST3")
      sleep 1
      Open.touch tmpdir.persist.glob("*").first
      assert_equal "TEST2", Persist.persist(dir.cache, type, :dir => tmpdir.persist, :update => dir.file3){ Open.read(dir.file3) }
    end
  end
end

