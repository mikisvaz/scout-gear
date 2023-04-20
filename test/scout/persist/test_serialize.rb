require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestPersistSerialize < Test::Unit::TestCase
  def test_string
    TmpFile.with_file do |tmpfile|
      obj = "TEST"
      Persist.save(obj, tmpfile, :string)
      assert_equal obj, Persist.load(tmpfile, :string)
    end
  end

  def test_string_io
    TmpFile.with_file do |tmpfile|
      obj = "TEST"
      Persist.save(StringIO.new(obj), tmpfile, :string)
      assert_equal obj, Persist.load(tmpfile, :string)
    end
  end

  def test_integer
    TmpFile.with_file do |tmpfile|
      obj = 1
      Persist.save(obj, tmpfile, :integer)
      assert_equal obj, Persist.load(tmpfile, :integer)
    end
  end

  def test_float
    TmpFile.with_file do |tmpfile|
      obj = 1.210202
      Persist.save(obj, tmpfile, :float)
      assert_equal obj, Persist.load(tmpfile, :float)
    end
  end

  def test_array
    TmpFile.with_file do |tmpfile|
      obj = %w(one two)
      Persist.save(obj, tmpfile, :array)
      assert_equal obj, Persist.load(tmpfile, :array)
    end
  end

  def test_integer_array
    TmpFile.with_file do |tmpfile|
      obj = [1, 2]
      Persist.save(obj, tmpfile, :integer_array)
      assert_equal obj, Persist.load(tmpfile, :integer_array)
    end
  end

  def test_float_array
    TmpFile.with_file do |tmpfile|
      obj = [1.1, 2.2]
      Persist.save(obj, tmpfile, :float_array)
      assert_equal obj, Persist.load(tmpfile, :float_array)
    end
  end

  def test_boolean_array
    TmpFile.with_file do |tmpfile|
      obj = [true, false, true]
      Persist.save(obj, tmpfile, :boolean_array)
      assert_equal obj, Persist.load(tmpfile, :boolean_array)
    end
  end

  def test_path_array
    TmpFile.with_file do |tmpfile|
      dir = Path.setup("test/dir")
      obj = [dir.foo, dir.bar]
      Persist.save(obj, tmpfile, :path_array)
      assert_equal obj, Persist.load(tmpfile, :path_array)
      assert_equal dir.foo.find, obj.first.find
    end
  end

  def test_path_array_hash
    TmpFile.with_file do |tmpfile|
      dir = Path.setup("test/dir")
      obj = [dir.foo, dir.bar]
      hash = {}
      Persist.save(obj, tmpfile, hash)
      assert_equal obj, Persist.load(tmpfile, hash)
      assert_equal dir.foo.find, obj.first.find
    end
  end
end

