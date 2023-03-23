require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestPath < Test::Unit::TestCase
  def test_join
    path = '/tmp'
    path.extend Path
    assert_equal '/tmp/foo', path.join(:foo)
    assert_equal '/tmp/foo/bar', path.join(:bar, :foo)
  end

  def test_get
    path = '/tmp'
    path.extend Path
    assert_equal '/tmp/foo', path[:foo]
    assert_equal '/tmp/foo/bar', path.foo[:bar]
    assert_equal '/tmp/foo/bar', path[:bar, :foo]
  end

  def test_slash
    path = '/tmp'
    path.extend Path
    assert_equal '/tmp/foo', path/:foo
    assert_equal '/tmp/foo/bar', path/:foo/:bar
    assert_equal '/tmp/foo/bar', path.foo/:bar
    assert_equal '/tmp/foo/bar', path./(:bar, :foo)
  end

  def test_setup
    path = 'tmp'
    Path.setup(path)
    assert_equal 'scout', path.namespace
    iii path.libdir
  end
end

