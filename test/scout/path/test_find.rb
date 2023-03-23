require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require 'scout/path'
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')
class TestPathFind < Test::Unit::TestCase
  def test_parts
    path = Path.setup("share/data/some_file", 'scout')
    assert_equal "share", path._toplevel
    assert_equal "data/some_file", path._subpath

    path = Path.setup("data", 'scout')
    assert_equal nil, path._toplevel
    assert_equal "data", path._subpath
  end

  def test_find_local
    map = File.join('/usr/local', "{TOPLEVEL}", "{PKGDIR}", "{SUBPATH}")
    path = Path.setup("share/data/some_file", 'scout')
    target = "/usr/local/share/scout/data/some_file"
    assert_equal target, Path.follow(path, map)
  end

  def test_find
    path = Path.setup("share/data/some_file", 'scout')
    assert_equal "/usr/share/scout/data/some_file", path.find(:usr)
  end
end

