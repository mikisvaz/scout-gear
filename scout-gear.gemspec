# Generated by juwelier
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Juwelier::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-
# stub: scout-gear 5.0.0 ruby lib

Gem::Specification.new do |s|
  s.name = "scout-gear".freeze
  s.version = "5.0.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Miguel Vazquez".freeze]
  s.date = "2023-04-26"
  s.description = "Temporary files, logs, etc.".freeze
  s.email = "mikisvaz@gmail.com".freeze
  s.executables = ["rbbt".freeze, "scout".freeze, "alias".freeze, "find".freeze, "glob".freeze, "task".freeze]
  s.extra_rdoc_files = [
    "LICENSE.txt",
    "README.rdoc"
  ]
  s.files = [
    ".document",
    ".gitmodules",
    ".vimproject",
    "LICENSE.txt",
    "README.rdoc",
    "Rakefile",
    "VERSION",
    "bin/rbbt",
    "bin/scout",
    "bin/scout_commands/alias",
    "bin/scout_commands/find",
    "bin/scout_commands/glob",
    "bin/scout_commands/workflow/task",
    "lib/scout-gear.rb",
    "lib/scout.rb",
    "lib/scout/cmd.rb",
    "lib/scout/concurrent_stream.rb",
    "lib/scout/exceptions.rb",
    "lib/scout/indiferent_hash.rb",
    "lib/scout/indiferent_hash/case_insensitive.rb",
    "lib/scout/indiferent_hash/options.rb",
    "lib/scout/log.rb",
    "lib/scout/log/color.rb",
    "lib/scout/log/color_class.rb",
    "lib/scout/log/fingerprint.rb",
    "lib/scout/log/progress.rb",
    "lib/scout/log/progress/report.rb",
    "lib/scout/log/progress/util.rb",
    "lib/scout/meta_extension.rb",
    "lib/scout/misc.rb",
    "lib/scout/misc/digest.rb",
    "lib/scout/misc/filesystem.rb",
    "lib/scout/misc/format.rb",
    "lib/scout/misc/insist.rb",
    "lib/scout/open.rb",
    "lib/scout/open/lock.rb",
    "lib/scout/open/remote.rb",
    "lib/scout/open/stream.rb",
    "lib/scout/open/util.rb",
    "lib/scout/path.rb",
    "lib/scout/path/find.rb",
    "lib/scout/path/tmpfile.rb",
    "lib/scout/path/util.rb",
    "lib/scout/persist.rb",
    "lib/scout/persist/open.rb",
    "lib/scout/persist/path.rb",
    "lib/scout/persist/serialize.rb",
    "lib/scout/resource.rb",
    "lib/scout/resource/path.rb",
    "lib/scout/resource/produce.rb",
    "lib/scout/resource/produce/rake.rb",
    "lib/scout/resource/scout.rb",
    "lib/scout/simple_opt.rb",
    "lib/scout/simple_opt/accessor.rb",
    "lib/scout/simple_opt/doc.rb",
    "lib/scout/simple_opt/get.rb",
    "lib/scout/simple_opt/parse.rb",
    "lib/scout/simple_opt/setup.rb",
    "lib/scout/tmpfile.rb",
    "lib/scout/workflow.rb",
    "lib/scout/workflow/definition.rb",
    "lib/scout/workflow/documentation.rb",
    "lib/scout/workflow/step.rb",
    "lib/scout/workflow/step/info.rb",
    "lib/scout/workflow/task.rb",
    "lib/scout/workflow/task/inputs.rb",
    "lib/scout/workflow/usage.rb",
    "lib/scout/workflow/util.rb",
    "lib/workflow-scout.rb",
    "scout-gear.gemspec",
    "test/scout/indiferent_hash/test_case_insensitive.rb",
    "test/scout/indiferent_hash/test_options.rb",
    "test/scout/log/test_progress.rb",
    "test/scout/misc/test_digest.rb",
    "test/scout/misc/test_filesystem.rb",
    "test/scout/misc/test_insist.rb",
    "test/scout/open/test_lock.rb",
    "test/scout/open/test_remote.rb",
    "test/scout/open/test_stream.rb",
    "test/scout/open/test_util.rb",
    "test/scout/path/test_find.rb",
    "test/scout/path/test_util.rb",
    "test/scout/persist/test_open.rb",
    "test/scout/persist/test_path.rb",
    "test/scout/persist/test_serialize.rb",
    "test/scout/resource/test_path.rb",
    "test/scout/resource/test_produce.rb",
    "test/scout/simple_opt/test_get.rb",
    "test/scout/simple_opt/test_parse.rb",
    "test/scout/simple_opt/test_setup.rb",
    "test/scout/test_cmd.rb",
    "test/scout/test_concurrent_stream.rb",
    "test/scout/test_indiferent_hash.rb",
    "test/scout/test_log.rb",
    "test/scout/test_meta_extension.rb",
    "test/scout/test_misc.rb",
    "test/scout/test_open.rb",
    "test/scout/test_path.rb",
    "test/scout/test_persist.rb",
    "test/scout/test_resource.rb",
    "test/scout/test_tmpfile.rb",
    "test/scout/test_workflow.rb",
    "test/scout/workflow/step/test_info.rb",
    "test/scout/workflow/task/test_inputs.rb",
    "test/scout/workflow/test_step.rb",
    "test/scout/workflow/test_task.rb",
    "test/scout/workflow/test_usage.rb",
    "test/scout/workflow/test_util.rb",
    "test/test_helper.rb",
    "test/test_scout-gear.rb"
  ]
  s.homepage = "http://github.com/mikisvaz/scout-gear".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.4.11".freeze
  s.summary = "basic gear for scouts".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<term-ansicolor>.freeze, [">= 0"])
  s.add_development_dependency(%q<rdoc>.freeze, ["~> 3.12"])
  s.add_development_dependency(%q<bundler>.freeze, ["~> 1.0"])
  s.add_development_dependency(%q<juwelier>.freeze, ["~> 2.1.0"])
  s.add_development_dependency(%q<simplecov>.freeze, [">= 0"])
end

