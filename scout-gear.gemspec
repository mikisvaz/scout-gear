# Generated by juwelier
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Juwelier::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-
# stub: scout-gear 10.1.0 ruby lib

Gem::Specification.new do |s|
  s.name = "scout-gear".freeze
  s.version = "10.1.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Miguel Vazquez".freeze]
  s.date = "2023-07-07"
  s.description = "Temporary files, logs, path, resources, persistence, workflows, TSV, etc.".freeze
  s.email = "mikisvaz@gmail.com".freeze
  s.executables = ["scout".freeze]
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
    "bin/scout",
    "doc/lib/scout/path.md",
    "doc/lib/scout/workflow/task.md",
    "lib/rbbt-scout.rb",
    "lib/scout-gear.rb",
    "lib/scout.rb",
    "lib/scout/offsite.rb",
    "lib/scout/offsite/exceptions.rb",
    "lib/scout/offsite/ssh.rb",
    "lib/scout/offsite/step.rb",
    "lib/scout/offsite/sync.rb",
    "lib/scout/semaphore.rb",
    "lib/scout/tsv.rb",
    "lib/scout/tsv/attach.rb",
    "lib/scout/tsv/change_id.rb",
    "lib/scout/tsv/dumper.rb",
    "lib/scout/tsv/index.rb",
    "lib/scout/tsv/open.rb",
    "lib/scout/tsv/parser.rb",
    "lib/scout/tsv/path.rb",
    "lib/scout/tsv/persist.rb",
    "lib/scout/tsv/persist/adapter.rb",
    "lib/scout/tsv/persist/fix_width_table.rb",
    "lib/scout/tsv/persist/serialize.rb",
    "lib/scout/tsv/persist/tokyocabinet.rb",
    "lib/scout/tsv/stream.rb",
    "lib/scout/tsv/transformer.rb",
    "lib/scout/tsv/traverse.rb",
    "lib/scout/tsv/util.rb",
    "lib/scout/tsv/util/filter.rb",
    "lib/scout/tsv/util/process.rb",
    "lib/scout/tsv/util/reorder.rb",
    "lib/scout/tsv/util/select.rb",
    "lib/scout/tsv/util/sort.rb",
    "lib/scout/tsv/util/unzip.rb",
    "lib/scout/work_queue.rb",
    "lib/scout/work_queue/exceptions.rb",
    "lib/scout/work_queue/socket.rb",
    "lib/scout/work_queue/worker.rb",
    "lib/scout/workflow.rb",
    "lib/scout/workflow/definition.rb",
    "lib/scout/workflow/deployment.rb",
    "lib/scout/workflow/deployment/orchestrator.rb",
    "lib/scout/workflow/documentation.rb",
    "lib/scout/workflow/step.rb",
    "lib/scout/workflow/step/config.rb",
    "lib/scout/workflow/step/dependencies.rb",
    "lib/scout/workflow/step/file.rb",
    "lib/scout/workflow/step/info.rb",
    "lib/scout/workflow/step/inputs.rb",
    "lib/scout/workflow/step/load.rb",
    "lib/scout/workflow/step/progress.rb",
    "lib/scout/workflow/step/provenance.rb",
    "lib/scout/workflow/step/status.rb",
    "lib/scout/workflow/task.rb",
    "lib/scout/workflow/task/dependencies.rb",
    "lib/scout/workflow/task/inputs.rb",
    "lib/scout/workflow/usage.rb",
    "lib/scout/workflow/util.rb",
    "lib/workflow-scout.rb",
    "scout-gear.gemspec",
    "scout_commands/alias",
    "scout_commands/doc",
    "scout_commands/find",
    "scout_commands/glob",
    "scout_commands/offsite",
    "scout_commands/rbbt",
    "scout_commands/resource/produce",
    "scout_commands/template",
    "scout_commands/update",
    "scout_commands/workflow/info",
    "scout_commands/workflow/install",
    "scout_commands/workflow/list",
    "scout_commands/workflow/task",
    "share/color/color_names",
    "share/color/diverging_colors.hex",
    "share/software/install_helpers",
    "share/templates/command",
    "share/templates/workflow.rb",
    "test/scout/offsite/test_ssh.rb",
    "test/scout/offsite/test_step.rb",
    "test/scout/offsite/test_sync.rb",
    "test/scout/offsite/test_task.rb",
    "test/scout/test_offsite.rb",
    "test/scout/test_semaphore.rb",
    "test/scout/test_tsv.rb",
    "test/scout/test_work_queue.rb",
    "test/scout/test_workflow.rb",
    "test/scout/tsv/persist/test_adapter.rb",
    "test/scout/tsv/persist/test_fix_width_table.rb",
    "test/scout/tsv/persist/test_tokyocabinet.rb",
    "test/scout/tsv/test_attach.rb",
    "test/scout/tsv/test_change_id.rb",
    "test/scout/tsv/test_dumper.rb",
    "test/scout/tsv/test_index.rb",
    "test/scout/tsv/test_open.rb",
    "test/scout/tsv/test_parser.rb",
    "test/scout/tsv/test_persist.rb",
    "test/scout/tsv/test_stream.rb",
    "test/scout/tsv/test_transformer.rb",
    "test/scout/tsv/test_traverse.rb",
    "test/scout/tsv/test_util.rb",
    "test/scout/tsv/util/test_filter.rb",
    "test/scout/tsv/util/test_process.rb",
    "test/scout/tsv/util/test_reorder.rb",
    "test/scout/tsv/util/test_select.rb",
    "test/scout/tsv/util/test_sort.rb",
    "test/scout/tsv/util/test_unzip.rb",
    "test/scout/work_queue/test_socket.rb",
    "test/scout/work_queue/test_worker.rb",
    "test/scout/workflow/deployment/test_orchestrator.rb",
    "test/scout/workflow/step/test_dependencies.rb",
    "test/scout/workflow/step/test_info.rb",
    "test/scout/workflow/step/test_load.rb",
    "test/scout/workflow/step/test_provenance.rb",
    "test/scout/workflow/step/test_status.rb",
    "test/scout/workflow/task/test_dependencies.rb",
    "test/scout/workflow/task/test_inputs.rb",
    "test/scout/workflow/test_definition.rb",
    "test/scout/workflow/test_documentation.rb",
    "test/scout/workflow/test_step.rb",
    "test/scout/workflow/test_task.rb",
    "test/scout/workflow/test_usage.rb",
    "test/scout/workflow/test_util.rb",
    "test/test_helper.rb",
    "test/test_scout-gear.rb",
    "test/test_scout.rb"
  ]
  s.homepage = "http://github.com/mikisvaz/scout-gear".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.4.13".freeze
  s.summary = "basic gear for scouts".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<scout-essentials>.freeze, [">= 0"])
  s.add_runtime_dependency(%q<net-ssh>.freeze, [">= 0"])
  s.add_runtime_dependency(%q<matrix>.freeze, [">= 0"])
  s.add_runtime_dependency(%q<RubyInline>.freeze, [">= 0"])
  s.add_development_dependency(%q<rdoc>.freeze, ["~> 3.12"])
  s.add_development_dependency(%q<bundler>.freeze, ["~> 1.0"])
  s.add_development_dependency(%q<juwelier>.freeze, ["~> 2.1.0"])
  s.add_development_dependency(%q<simplecov>.freeze, [">= 0"])
end

