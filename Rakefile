# encoding: utf-8

ENV["BRANCH"] = 'main'

require 'rubygems'
require 'rake'

require 'juwelier'
Juwelier::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://guides.rubygems.org/specification-reference/ for more options
  gem.name = "scout-gear"
  gem.homepage = "http://github.com/mikisvaz/scout-gear"
  gem.license = "MIT"
  gem.summary = %Q{basic gear for scouts}
  gem.description = %Q{Scout gear: workflow, TSVs, persistence, entities, associations, and knowledge_bases.}
  gem.email = "mikisvaz@gmail.com"
  gem.authors = ["Miguel Vazquez"]

  # Include your dependencies below. Runtime dependencies are required when using your gem,
  # and development dependencies are only needed for development (ie running rake tasks, tests, etc)
  #  gem.add_runtime_dependency 'jabber4r', '> 0.1'
  #  gem.add_development_dependency 'rspec', '> 1.2.3'
  gem.add_runtime_dependency 'scout-essentials'
  gem.add_runtime_dependency 'net-ssh'
  gem.add_runtime_dependency 'matrix'
  gem.add_runtime_dependency 'RubyInline'
  gem.add_runtime_dependency 'csv'
  #gem.add_runtime_dependency 'tokyocabinet'

  gem.add_development_dependency "juwelier", "~> 2.1.0"
end
Juwelier::RubygemsDotOrgTasks.new

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  ENV["SCOUT_LOG"] = "NONE"
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
  test.warning = false
end

desc "Code coverage detail"
task :simplecov do
  ENV['COVERAGE'] = "true"
  Rake::Task['test'].execute
end

task :default => :test

require 'rdoc/task'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "scout-gear #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
