# Synthesis Report

> **Non-normative.** This document cross-checks investigation artifacts and
> maps them to target documentation files.

## Investigation coverage

| Artifact | Subsystems covered | Lines |
|----------|-------------------|-------|
| `00_scope_and_themes.md` | All (overview, source structure) | 150 |
| `workflow-engine-analysis.md` | Workflow, Task, Step, deployment, provenance | 213 |
| `tsv-internals-analysis.md` | TSV, Parser, Dumper, Transformer, traverse, index, attach | 221 |
| `entity-association-kb-analysis.md` | Entity, Association, KnowledgeBase, Traverser | 265 |
| `persistence-concurrency-analysis.md` | Persist engines, TSVAdapter, WorkQueue, Semaphore | 316 |
| `design-philosophy-analysis.md` | Coding conventions, idioms, anti-patterns | 259 |

## Gap analysis

After reviewing all artifacts:

1. **TSV attach/join** — Covered in `tsv-internals-analysis.md` but could use
   more detail on the `match_keys` auto-detection logic. Sufficient for
   developer docs; user docs should focus on the API.

2. **CLI commands** — Not deeply investigated. The old `doc/Workflow.md`
   contains a CLI section. Need to check `scout_commands/` for the full
   command list before writing the user guide.

3. **Documentation generation** — `Workflow#documentation` auto-generates
   docs. Mentioned in workflow analysis but not deeply explored. Acceptable
   for now.

4. **Monitor** — `lib/scout/monitor.rb` exists but was not investigated.
   It's a minor utility for job monitoring; low priority.

## Target file mapping

### User documentation (`doc/user/`)

| File | Source research | Description |
|------|----------------|-------------|
| `BuildingWorkflows.md` | workflow-engine-analysis | Defining tasks, inputs, dependencies, helpers; running jobs |
| `ProcessingTabularData.md` | tsv-internals-analysis | Opening, creating, transforming, filtering TSV data |
| `WorkingWithEntities.md` | entity-association-kb-analysis | Defining entity types, properties, identifier translation |
| `ManagingRelationships.md` | entity-association-kb-analysis | Associations, KnowledgeBase registration, querying, traversal |
| `RunningParallelWork.md` | persistence-concurrency-analysis | WorkQueue for multi-process parallelism |
| `CachingData.md` | persistence-concurrency-analysis | Persist.tsv, choosing engines, annotation persistence |
| `Cookbook.md` | All | Practical recipes combining multiple subsystems |

### Developer documentation (`doc/developer/`)

| File | Source research | Description |
|------|----------------|-------------|
| `Architecture.md` | 00_scope_and_themes | Subsystem map, dependency graph, module relationships |
| `DesignPrinciples.md` | design-philosophy-analysis | Coding philosophy, idiomatic patterns, anti-patterns |
| `WorkflowEngine.md` | workflow-engine-analysis | Task lifecycle, Step execution, dependency resolution, deployment |
| `TSVInternals.md` | tsv-internals-analysis | Parser/Dumper/Transformer pipeline, traverse, indexing, attach |
| `EntitySystem.md` | entity-association-kb-analysis | Property dispatch, format registry, Association indexing, KB traversal |
| `PersistenceEngines.md` | persistence-concurrency-analysis | Engine dispatch, TokyoCabinet/FWT/PackedIndex/Sharder, TSVAdapter |
| `ConcurrencyModel.md` | persistence-concurrency-analysis | WorkQueue fork+IPC, Semaphore, reader thread |

### Top-level

| File | Description |
|------|-------------|
| `StartHere.md` | Entry point, routing readers to user/developer/research |
| `Improvements.md` | Actionable recommendations from all investigations |

## Writing priority

1. `StartHere.md` (needed first to define structure)
2. User docs batch 1: BuildingWorkflows, ProcessingTabularData, WorkingWithEntities
3. User docs batch 2: ManagingRelationships, RunningParallelWork, CachingData, Cookbook
4. Developer docs batch 1: Architecture, DesignPrinciples, WorkflowEngine
5. Developer docs batch 2: TSVInternals, EntitySystem, PersistenceEngines, ConcurrencyModel
6. Improvements.md
7. Remove old docs
8. Validation

## Cross-reference strategy

- scout-essentials concepts (annotations, persistence, paths, streams) →
  GitHub URLs: `https://github.com/mikisvaz/scout-essentials/blob/main/doc/...`
- Internal cross-references use relative paths within `doc/`
- Research artifacts referenced from developer docs via relative paths to `../research/`

## Improvements identified

From all investigations:

1. `Step#cleaned_dependencies` always returns `[]` (dead code)
2. `NilFloat = -999.999` sentinel can collide with real data
3. `NilInt = -999` sentinel can collide with real data
4. `'nil'` string sentinel in StringSerializer can collide with real data
5. `Entity::FORMATS` global registry has no namespacing
6. Traverser's `clean_matches` uses `.partition("~")` which is fragile
7. WorkQueue closures must be Marshal-serializable (undocumented constraint)
8. `Semaphore` silently fails if RubyInline/C compiler unavailable
9. TokyoCabinet connection caching in `Persist::CONNECTIONS` may reuse stale connections
10. `SCOUT_EXPLICIT_STREAMING` environment variable is undocumented
11. `task_alias` cleanup logic is complex with many config-dependent branches
12. PackedIndex mask is fixed at creation; no migration path
13. Sharder shard_function must be deterministic (undocumented invariant)
14. The `info` serializer format (JSON) can fail on non-JSON-serializable exceptions
15. `Monitor` module is undocumented
16. TSV `attach` auto-detection of match keys can produce surprising results
