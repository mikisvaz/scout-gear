require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestPersist < Test::Unit::TestCase
  def test_string
    Log.with_severity 0 do
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
  end

  def test_float_array
    Log.with_severity 0 do
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
  end

  def test_string_update
    Log.with_severity 0 do
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
  end

  def test_stream
    Log.with_severity 0 do
      TmpFile.with_file do |tmpfile|
        Path.setup(tmpfile)
        obj = "TEST\nTEST"
        stream = StringIO.new obj
        type = :string
        res = Persist.persist(tmpfile, :stream, :dir => tmpdir.persist){ stream }
        assert IO === res
        assert_equal obj, res.read
        assert_equal obj, Persist.persist(tmpfile, :stream, :dir => tmpdir.persist){ raise ScoutException }.read
        assert IO === Persist.persist(tmpfile, :stream, :dir => tmpdir.persist){ raise ScoutException }
        assert_equal obj, Persist.persist(tmpfile, :stream, :dir => tmpdir.persist){ raise ScoutException }.read
      end
    end
  end
end

