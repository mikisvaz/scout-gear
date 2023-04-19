require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')
require 'scout/resource'

class TestResourcePath < Test::Unit::TestCase
  module TestResource
    extend Resource

    self.subdir = Path.setup('tmp/test-resource_alt')

    claim self.tmp.test.string, :string, "TEST"
  end

  def teardown
    FileUtils.rm_rf TestResource.root.find
  end

  def test_read
    assert_include TestResource.tmp.test.string.read, "TEST"
  end

  def test_open
    str = ""
    TestResource.tmp.test.string.open do |f|
      str = f.read
    end
    assert_include str, "TEST"
  end
end

