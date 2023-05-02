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

  def tmpdir
    @tmpdir = Path.setup('tmp/test_tmpdir').find
  end

  setup do
    Log::ProgressBar.default_severity = 0
    Persist.cache_dir = tmpdir.var.cache
    Open.remote_cache_dir = tmpdir.var.cache
    Workflow.directory = tmpdir.var.jobs
    Workflow.workflows.each{|wf| wf.directory = Workflow.directory[wf.name] }
  end
  
  teardown do
    Open.rm_rf tmpdir
  end
end
