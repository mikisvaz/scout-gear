require 'simplecov'

module SimpleCov::Configuration
  def clean_filters
    @filters = []
  end
end

SimpleCov.configure do
  clean_filters
  load_adapter 'test_frameworks'
end

ENV["COVERAGE"] && SimpleCov.start do
  add_filter "/.rvm/"
end
require 'rubygems'
require 'test/unit'

$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
#require 'scout/helper/misc/development'
require 'scout/tmpfile'
require 'scout/log'
require 'scout/open'
require 'scout/persist'
require 'scout/workflow'

class Test::Unit::TestCase

  def assert_equal_path(path1, path2)
    assert_equal File.expand_path(path1), File.expand_path(path2)
  end

  def tmpdir
    @tmpdir ||= Path.setup('tmp/test_tmpdir').find
  end

  setup do
    TmpFile.tmpdir = tmpdir.tmpfiles
    Log::ProgressBar.default_severity = 0
    Persist.cache_dir = tmpdir.var.cache
    Persist::MEMORY_CACHE.clear
    Open.remote_cache_dir = tmpdir.var.cache
    Workflow.directory = tmpdir.var.jobs
    Workflow.workflows.each{|wf| wf.directory = Workflow.directory[wf.name] }
    Entity.entity_property_cache = tmpdir.entity_properties if defined?(Entity)
  end
  
  teardown do
    Open.rm_rf tmpdir
  end

  def self.datadir_test
    Path.setup(File.join(File.dirname(__FILE__), 'data'))
  end

  def self.datafile_test(file)
    datadir_test[file.to_s]
  end

  def datadir_test
    Test::Unit::TestCase.datadir_test
  end

  def datafile_test(file)
    Test::Unit::TestCase.datafile_test(file)
  end
end
