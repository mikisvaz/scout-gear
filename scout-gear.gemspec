# Generated by juwelier
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Juwelier::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-
# stub: scout-gear 10.7.7 ruby lib

Gem::Specification.new do |s|
  s.name = "scout-gear".freeze
  s.version = "10.7.7".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Miguel Vazquez".freeze]
  s.date = "2025-04-11"
  s.description = "Scout gear: workflow, TSVs, persistence, entities, associations, and knowledge_bases.".freeze
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
    "lib/scout/association.rb",
    "lib/scout/association/fields.rb",
    "lib/scout/association/index.rb",
    "lib/scout/association/item.rb",
    "lib/scout/association/util.rb",
    "lib/scout/entity.rb",
    "lib/scout/entity/format.rb",
    "lib/scout/entity/identifiers.rb",
    "lib/scout/entity/named_array.rb",
    "lib/scout/entity/object.rb",
    "lib/scout/entity/property.rb",
    "lib/scout/knowledge_base.rb",
    "lib/scout/knowledge_base/description.rb",
    "lib/scout/knowledge_base/enrichment.rb",
    "lib/scout/knowledge_base/entity.rb",
    "lib/scout/knowledge_base/list.rb",
    "lib/scout/knowledge_base/query.rb",
    "lib/scout/knowledge_base/registry.rb",
    "lib/scout/knowledge_base/traverse.rb",
    "lib/scout/persist/engine.rb",
    "lib/scout/persist/engine/fix_width_table.rb",
    "lib/scout/persist/engine/packed_index.rb",
    "lib/scout/persist/engine/sharder.rb",
    "lib/scout/persist/engine/tkrzw.rb",
    "lib/scout/persist/engine/tokyocabinet.rb",
    "lib/scout/persist/tsv.rb",
    "lib/scout/persist/tsv/adapter.rb",
    "lib/scout/persist/tsv/adapter/base.rb",
    "lib/scout/persist/tsv/adapter/fix_width_table.rb",
    "lib/scout/persist/tsv/adapter/packed_index.rb",
    "lib/scout/persist/tsv/adapter/sharder.rb",
    "lib/scout/persist/tsv/adapter/tkrzw.rb",
    "lib/scout/persist/tsv/adapter/tokyocabinet.rb",
    "lib/scout/persist/tsv/serialize.rb",
    "lib/scout/semaphore.rb",
    "lib/scout/tsv.rb",
    "lib/scout/tsv/annotation.rb",
    "lib/scout/tsv/annotation/repo.rb",
    "lib/scout/tsv/attach.rb",
    "lib/scout/tsv/change_id.rb",
    "lib/scout/tsv/change_id/translate.rb",
    "lib/scout/tsv/csv.rb",
    "lib/scout/tsv/dumper.rb",
    "lib/scout/tsv/index.rb",
    "lib/scout/tsv/open.rb",
    "lib/scout/tsv/parser.rb",
    "lib/scout/tsv/path.rb",
    "lib/scout/tsv/stream.rb",
    "lib/scout/tsv/transformer.rb",
    "lib/scout/tsv/traverse.rb",
    "lib/scout/tsv/util.rb",
    "lib/scout/tsv/util/filter.rb",
    "lib/scout/tsv/util/melt.rb",
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
    "lib/scout/workflow/deployment/queue.rb",
    "lib/scout/workflow/deployment/trace.rb",
    "lib/scout/workflow/documentation.rb",
    "lib/scout/workflow/entity.rb",
    "lib/scout/workflow/exceptions.rb",
    "lib/scout/workflow/export.rb",
    "lib/scout/workflow/path.rb",
    "lib/scout/workflow/persist.rb",
    "lib/scout/workflow/step.rb",
    "lib/scout/workflow/step/archive.rb",
    "lib/scout/workflow/step/children.rb",
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
    "lib/scout/workflow/task/info.rb",
    "lib/scout/workflow/task/inputs.rb",
    "lib/scout/workflow/usage.rb",
    "lib/scout/workflow/util.rb",
    "lib/workflow-scout.rb",
    "scout-gear.gemspec",
    "scout_commands/alias",
    "scout_commands/batch/clean",
    "scout_commands/batch/list",
    "scout_commands/doc",
    "scout_commands/find",
    "scout_commands/glob",
    "scout_commands/kb/config",
    "scout_commands/kb/entities",
    "scout_commands/kb/list",
    "scout_commands/kb/query",
    "scout_commands/kb/register",
    "scout_commands/kb/show",
    "scout_commands/kb/traverse",
    "scout_commands/log",
    "scout_commands/rbbt",
    "scout_commands/resource/produce",
    "scout_commands/resource/sync",
    "scout_commands/template",
    "scout_commands/update",
    "scout_commands/workflow/cmd",
    "scout_commands/workflow/info",
    "scout_commands/workflow/install",
    "scout_commands/workflow/list",
    "scout_commands/workflow/process",
    "scout_commands/workflow/prov",
    "scout_commands/workflow/task",
    "scout_commands/workflow/trace",
    "scout_commands/workflow/write_info",
    "share/color/color_names",
    "share/color/diverging_colors.hex",
    "share/software/install_helpers",
    "share/templates/command",
    "share/templates/workflow.rb",
    "test/data/person/README.md",
    "test/data/person/brothers",
    "test/data/person/identifiers",
    "test/data/person/marriages",
    "test/data/person/parents",
    "test/scout/association/test_fields.rb",
    "test/scout/association/test_index.rb",
    "test/scout/association/test_item.rb",
    "test/scout/entity/test_format.rb",
    "test/scout/entity/test_identifiers.rb",
    "test/scout/entity/test_named_array.rb",
    "test/scout/entity/test_object.rb",
    "test/scout/entity/test_property.rb",
    "test/scout/knowledge_base/test_description.rb",
    "test/scout/knowledge_base/test_enrichment.rb",
    "test/scout/knowledge_base/test_entity.rb",
    "test/scout/knowledge_base/test_list.rb",
    "test/scout/knowledge_base/test_query.rb",
    "test/scout/knowledge_base/test_registry.rb",
    "test/scout/knowledge_base/test_traverse.rb",
    "test/scout/persist/engine/test_fix_width_table.rb",
    "test/scout/persist/engine/test_packed_index.rb",
    "test/scout/persist/engine/test_sharder.rb",
    "test/scout/persist/engine/test_tkrzw.rb",
    "test/scout/persist/engine/test_tokyocabinet.rb",
    "test/scout/persist/test_tsv.rb",
    "test/scout/persist/tsv/adapter/test_base.rb",
    "test/scout/persist/tsv/adapter/test_fix_width_table.rb",
    "test/scout/persist/tsv/adapter/test_packed_index.rb",
    "test/scout/persist/tsv/adapter/test_serialize.rb",
    "test/scout/persist/tsv/adapter/test_sharder.rb",
    "test/scout/persist/tsv/adapter/test_tkrzw.rb",
    "test/scout/persist/tsv/adapter/test_tokyocabinet.rb",
    "test/scout/persist/tsv/test_serialize.rb",
    "test/scout/test_association.rb",
    "test/scout/test_entity.rb",
    "test/scout/test_knowledge_base.rb",
    "test/scout/test_semaphore.rb",
    "test/scout/test_tsv.rb",
    "test/scout/test_work_queue.rb",
    "test/scout/test_workflow.rb",
    "test/scout/tsv/annotation/test_repo.rb",
    "test/scout/tsv/change_id/test_translate.rb",
    "test/scout/tsv/test_annotation.rb",
    "test/scout/tsv/test_attach.rb",
    "test/scout/tsv/test_change_id.rb",
    "test/scout/tsv/test_csv.rb",
    "test/scout/tsv/test_dumper.rb",
    "test/scout/tsv/test_index.rb",
    "test/scout/tsv/test_open.rb",
    "test/scout/tsv/test_parser.rb",
    "test/scout/tsv/test_path.rb",
    "test/scout/tsv/test_stream.rb",
    "test/scout/tsv/test_transformer.rb",
    "test/scout/tsv/test_traverse.rb",
    "test/scout/tsv/test_util.rb",
    "test/scout/tsv/util/test_filter.rb",
    "test/scout/tsv/util/test_melt.rb",
    "test/scout/tsv/util/test_process.rb",
    "test/scout/tsv/util/test_reorder.rb",
    "test/scout/tsv/util/test_select.rb",
    "test/scout/tsv/util/test_sort.rb",
    "test/scout/tsv/util/test_unzip.rb",
    "test/scout/work_queue/test_socket.rb",
    "test/scout/work_queue/test_worker.rb",
    "test/scout/workflow/deployment/test_orchestrator.rb",
    "test/scout/workflow/deployment/test_trace.rb",
    "test/scout/workflow/step/test_archive.rb",
    "test/scout/workflow/step/test_children.rb",
    "test/scout/workflow/step/test_dependencies.rb",
    "test/scout/workflow/step/test_info.rb",
    "test/scout/workflow/step/test_load.rb",
    "test/scout/workflow/step/test_provenance.rb",
    "test/scout/workflow/step/test_status.rb",
    "test/scout/workflow/task/test_dependencies.rb",
    "test/scout/workflow/task/test_info.rb",
    "test/scout/workflow/task/test_inputs.rb",
    "test/scout/workflow/test_definition.rb",
    "test/scout/workflow/test_documentation.rb",
    "test/scout/workflow/test_entity.rb",
    "test/scout/workflow/test_path.rb",
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
  s.rubygems_version = "3.6.5".freeze
  s.summary = "basic gear for scouts".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<scout-essentials>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<net-ssh>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<matrix>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<RubyInline>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<juwelier>.freeze, ["~> 2.1.0".freeze])
end

