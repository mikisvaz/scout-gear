require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestSync < Test::Unit::TestCase
  def test_sync
    TmpFile.with_path do |tmpdir|
      tmpdir = Scout.tmp.tmpdir_sync
      tmpdir.dir1.foo.write("FOO")
      tmpdir.dir1.bar.write("BAR")

      TmpFile.with_path do |tmpdir2|
        Misc.in_dir tmpdir2 do
          SSHLine.sync([tmpdir.dir1], map: :current)

          assert tmpdir2.glob("**/*").select{|f| f.include?('foo') }.any?
        end
      end
    end
  end

  def test_sync_dir_map
    TmpFile.with_path do |tmpdir|
      tmpdir = Scout.tmp.tmpdir_sync
      tmpdir.dir1.foo.write("FOO")
      tmpdir.dir1.bar.write("BAR")

      TmpFile.with_path do |tmpdir2|
        SSHLine.sync([tmpdir.dir1], map: tmpdir2)
        Misc.in_dir tmpdir2 do
          assert tmpdir2.glob("**/*").select{|f| f.include?('foo') }.any?
        end
      end
    end
  end
end

