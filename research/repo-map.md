# scout-gear — canonical repository map

> Concise, seedable map. All paths relative to repo root
> (`/bulk/mvazque2/git/scout-gear`). Baseline rev `8a3a514` (campaign
> HEAD; doc-promotion commits 3d9c26b..HEAD).
> **Rule:** source is authoritative; use `lib/scout/tsv/.save/**` only as
> historical reference — the live persistence layer is `lib/scout/persist/**`.
> **Doc-tree status (audit update):** `doc/` now = 18 files — the original 16
> plus `user/HPCBatchExecution.md` (HPC/batch execution) and
> `user/UsingTheCLI.md` (CLI promotion, later batch).

## 1. Identity & relationships

- Gem: `scout-gear` (`scout-gear.gemspec`, `VERSION`). Executable: `bin/scout`.
- Depends on **scout-essentials** (rbbt lineage) for: CMD/Open/Log/Misc/Path/
  TmpFile/Lock/IndiferentHash/Config/annotations/TSV-core-annotation and
  `Persist.persist` core — NOT re-implemented here (verified P050/P051:
  `Persist.persist`/`Persist.load`/`Persist.save` resolve to
  `~/git/scout-essentials/lib/scout/persist.rb`; `TSV` core lives in
  scout-gear `lib/scout/tsv.rb`).
- Implements **here**: workflow engine + HPC orchestration, TSV subsystem,
  Association/KnowledgeBase, Entity, persistence engines/adapters for TSV,
  WorkQueue, ScoutSemaphore, CLI (`scout` binary + `scout_commands/**`).
- **scout-camp** deploys workflows; scout-gear implements the engine/scheduler
  machinery (verify ownership claims per-concept, never by repo proximity).
- Downstream evidence repos: `~/git/workflows/{Finances,AGS,genomics,
  SyntheticCancerGenome}` (all four under `workflows/`, both spellings noted);
  HPC config examples `~/.scout/etc/batch/*.yaml`.

## 2. Source layout (`lib/`, 113 files)

| Area | Path | Contents (key files) |
|---|---|---|
| **Entry** | `lib/scout.rb`, `lib/scout-gear.rb`, `lib/workflow-scout.rb` | requires; `scout.rb` loads all subsystems |
| **Workflow engine** | `lib/scout/workflow/**` (34 files) | `workflow.rb` (Workflow class), `definition.rb`, `task.rb` + `task/{dependencies,inputs,info}.rb`, `step.rb` + `step/{archive,children,config,dependencies,file,info,inputs,load,progress,provenance,status}.rb`, `exceptions.rb`, `documentation.rb`, `export.rb`, `persist.rb`, `path.rb`, `usage.rb`, `util.rb`, `entity.rb` |
| **Deployment/HPC** | `lib/scout/workflow/deployment/**` (13 files) | `deployment.rb`, `local.rb`, `queue.rb`, `trace.rb`, `scheduler.rb` + `scheduler/{job,lfs,pbs,slurm}.rb`, `orchestrator/{batches,chains,rules,workload}.rb` |
| **TSV** | `lib/scout/tsv/**` (23 files) | `tsv.rb` (core), `parser.rb`, `dumper.rb`, `attach.rb`, `index.rb`, `stream.rb`, `path.rb`, `open.rb`, `annotation.rb`+`annotation/repo.rb`, `change_id.rb`+`translate.rb`, `traverse.rb`, `transformer.rb`, `util/{filter,melt,process,reorder,select,sort,unzip}.rb`, `csv.rb` |
| **Persistence** | `lib/scout/persist/**` (16 files) | `engine.rb`, `tsv.rb`, `tsv/adapter.rb` + `adapter/{base,fix_width_table,packed_index,sharder,tkrzw,tokyocabinet}.rb`, `tsv/serialize.rb` |
| **Association** | `lib/scout/association/**` (5 files) | `association.rb`, `fields.rb`, `index.rb`, `item.rb`, `util.rb` |
| **KnowledgeBase** | `lib/scout/knowledge_base/**` (9 files) | `knowledge_base.rb`, `registry.rb`, `query.rb`, `traverse.rb`, `list.rb`, `entity.rb`, `enrichment.rb`, `description.rb` |
| **Entity** | `lib/scout/entity/**` (7 files) | `entity.rb`, `object.rb`, `property.rb`, `identifiers.rb`, `format.rb`, `named_array.rb` |
| **Concurrency** | `lib/scout/work_queue/**` (4), `lib/scout/semaphore.rb`, `lib/scout/monitor.rb` | WorkQueue (SOCK-based multi-process), ScoutSemaphore (POSIX named semaphores), monitor |
| **Standalone** | `lib/scout/association.rb` etc. loaded via `scout.rb` | — |

## 3. Tests

`test/scout/**` mirrors `lib/scout/**` (tsv, persist, association, entity,
knowledge_base, work_queue, workflow/{step,task,deployment/{scheduler,orchestrator}}),
plus `test/data/**` fixtures. Tests are behavior evidence for subtle semantics.

## 4. CLI

- `bin/scout` — single executable; dispatches subcommands.
- `scout_commands/**` (35 files) define them: 15 top-level entries, five
  of them subcommand families (`batch`, `kb`, `resource`, `system`,
  `workflow`) — `batch/{clean,list,tail}`,
  `kb/{config,entities,list,query,register,show,traverse}`,
  `resource/{produce,sync}`, `system/{clean,status}`,
  `workflow/{cmd,example,info,install,list,process,prov,task,trace,
  write_info}`. See `doc/user/UsingTheCLI.md` for the dispatch contract.
- `share/templates/workflow.rb` + `share/templates/command` — scaffolding for
  `scout workflow install`/`scout template`.

## 5. Documentation (audit target)

`doc/` = 18 files (post-audit, post-CLI-promotion): `StartHere.md`,
`Improvements.md`,
`developer/{Architecture,ConcurrencyModel,DesignPrinciples,EntitySystem,
PersistenceEngines,TSVInternals,WorkflowEngine}.md` and
`user/{BuildingWorkflows,CachingData,Cookbook,HPCBatchExecution,
ManagingRelationships,ProcessingTabularData,RunningParallelWork,UsingTheCLI,
WorkingWithEntities}.md`. Plus root
`README.md`, `README.rdoc` (legacy).

## 6. Configuration / persistence / integrations

- Config: Scout::Config via scout-essentials; `~/.scout/etc/**` user config
  (`batch/*.yaml` for HPC chains/defaults/rules), `var/` directories under
  workflows. Batch config keys: `defaults`, `chains`, `keys`, `rules`,
  `cont`/`skip`/`remove_dep_tasks`/`batch_dependencies`, `system, batch,
  scheduler` (BATCH_SYSTEM env).
- Step state on disk: step directories with `.info` YAML files (statuses:
  waiting/setup/start/done/error/aborted), `files/`, `tmp/`; job dirs under
  `var/jobs` (config key `var, jobs`).
- Persistence: `Persist.cache_dir` (`~/.scout/var/cache/persistence`) via
  scout-essentials `Persist` + scout-gear engines (TokyoCabinet HDB/BDB native
  gem, FixWidthTable 'fwt', PackedIndex 'pki', Sharder; Tkrzw adapter present
  but NOT selectable via `open_database` — dormant). Engine dispatch
  `persist/tsv.rb:27-48`; `:big` suffix = TLARGE|TDEFLATE tuning.
- External integrations: SLURM/PBS/LSF(lfs.rb, filename typo)/Singularity,
  orchestration YAML rules (`orchestrator/rules.rb` + `~/.scout/etc/batch`).
- Extension mechanisms: workflow DSL (`Workflow`, `input`, `dep`, `task`,
  `export`, `helper`, `extend_entity`, `include_workflow`), KB registry,
  persist adapters, scheduler types (`local`/`queue`/`SLURM`/`LSF`/`PBS`).

## 6b. Research artifacts (campaign output)

- `research/*-probes.md` (8 ledgers: association-kb, cli, concurrency,
  deployment-hpc, entity, persistence, tsv, workflow-engine) —
  non-normative probe ledgers backing the promoted doc claims. Evidence
  chains live in Cortex artifacts `scout-gear/<subject>.md` (map
  `current`); receipts cite `Observation/probe/<name>_<hash>.json` jobs.
- Pre-campaign analyses (`00_scope_and_themes`, `design-philosophy`,
  `downstream-usage`, `entity-association-kb-analysis`, `identifiers-
  mechanism`, `persistence-concurrency-analysis`, `tsv-internals-analysis`,
  `workflow-engine-analysis`, `synthesis-report`, `validation-report`)
  — earlier batches, unchanged by the consolidation campaign.

## 7. Vendored / legacy / non-source

- `lib/scout/tsv/.save/persist/**` — historical copy of the persistence layer
  (superseded by `lib/scout/persist/**`); treat as legacy, not live API.
- `modules/` empty; `pkg/`, `chats/`, `sandbox/`, `tmp/` non-source.
- `README.rdoc` legacy; `share/color/**` data files for color palettes.

## 8. Likely public / downstream interfaces

1. `Scout.workflow`/`Workflow` DSL (`task`, `input`, `dep`, `export`,
   `produce`, `extend`, `when_all`, `compute`, `helper`, `task_alias`,
   `include_workflow`).
2. `Scout::Step` lifecycle + `scout workflow task/…` CLI.
3. `Scout::TSV` (open/parse/attach/index/traverse/stream/dumper/CSV).
4. `Scout::AssociationItem`, `Scout::KnowledgeBase` (register/query/traverse).
5. `Scout::Entity` / `Entity.extend` DSL + `Entity::Identified` via
   `add_identifiers`.
6. `Persist.tsv` + engines; TSV adapters (`Persist::TSV::Adapter::*`).
7. `Scout::WorkQueue` / `ScoutSemaphore` (parallelism, semaphore).
8. `scout` CLI + `scout_commands/**` (user-facing).
9. Deployment/orchestration YAML + scheduler DSL (chains/rules/workload).

## 9. Audit tranches (partition of `lib/`, no file skipped)

| # | Tranche | Files |
|---|---|---|
| T1 | Core & entry | `scout.rb`, `scout-gear.rb`, `workflow-scout.rb`, `monitor.rb`, `semaphore.rb`, `work_queue/**` |
| T2 | TSV core | `tsv.rb`, `parser.rb`, `dumper.rb`, `open.rb`, `path.rb`, `stream.rb`, `csv.rb` |
| T3 | TSV transforms | `attach.rb`, `index.rb`, `change_id.rb`, `translate.rb`, `traverse.rb`, `transformer.rb`, `util/**` |
| T4 | Persistence | `persist/**` (all 16) + note on `tsv/.save/**` legacy |
| T5 | Entity + Association | `entity/**`, `association/**` |
| T6 | KnowledgeBase | `knowledge_base/**` |
| T7 | Workflow engine I | `workflow.rb`, `definition.rb`, `task.rb`, `task/**` |
| T8 | Workflow engine II | `step.rb`, `step/**` |
| T9 | Deployment/HPC | `deployment/**` (13) |
| T10 | CLI & integration | `bin/scout`, `scout_commands/**`, `share/templates/**`, gemspec/Rakefile |
