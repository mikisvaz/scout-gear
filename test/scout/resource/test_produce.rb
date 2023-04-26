require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'../resource')

class TestResourceUnit < Test::Unit::TestCase
  module TestResource
    extend Resource

    self.subdir = Path.setup('tmp/test-resource')

    claim self.tmp.test.google, :url, "http://google.com"
    claim self.tmp.test.string, :string, "TEST"
    claim self.tmp.test.proc, :proc do
      "PROC TEST"
    end

    claim self.tmp.test.rakefiles.Rakefile , :string , <<-EOF
file('foo') do |t|
  Open.write(t.name, "FOO")
end

rule(/.*/) do |t|
  Open.write(t.name, "OTHER")
end
    EOF

    claim self.tmp.test.work.footest, :rake, TestResource.tmp.test.rakefiles.Rakefile

    claim self.tmp.test.work.file_proc, :file_proc do |file,filename|
      Open.write(filename, file)
      nil
    end
  end

  def teardown
    FileUtils.rm_rf TestResource.root.find
  end

  def test_proc
    Log.with_severity 0 do
      TestResource.produce TestResource.tmp.test.proc
      assert_include File.open(TestResource.tmp.test.proc.find).read, "PROC TEST"
    end
  end

  def test_string
    Log.with_severity 0 do
      TestResource.produce TestResource.tmp.test.string
      assert_include File.open(TestResource.tmp.test.string.find).read, "TEST"
    end
  end

  def test_url
    Log.with_severity 0 do
      TestResource.produce TestResource.tmp.test.google
      assert_include File.open(TestResource.tmp.test.google.find).read, "html"
    end
  end

  def test_rake
    Log.with_severity 0 do
      TestResource.produce TestResource.tmp.test.work.footest.foo
      TestResource.produce TestResource.tmp.test.work.footest.bar
      TestResource.produce TestResource.tmp.test.work.footest.foo_bar
      assert_include File.open(TestResource.tmp.test.work.footest.foo.find).read, "FOO"
      assert_include File.open(TestResource.tmp.test.work.footest.bar.find).read, "OTHER"
      assert_include File.open(TestResource.tmp.test.work.footest.foo_bar.find).read, "OTHER"
    end
  end

end
