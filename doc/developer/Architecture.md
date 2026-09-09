# Architecture

This document provides a high-level map of scout-gear's subsystems, their
responsibilities, and how they interact.

It is intended for framework contributors who need to understand the overall
structure before diving into specific subsystems.

## Subsystem map

```
┌───────────────────────────────────────────────────────────────────┐
│                        Workflow Engine                             │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐  │
│  │  Task (DSL)  │──│ Step (exec)  │──│ Deployment              │  │
│  │ definition/  │  │ step/        │ │ (scheduler: SLURM/PBS/  │  │
│  │ task.rb      │  │              │ │  LSF; local/queue)      │  │
│  └──────────────┘  └──────────────┘  └────────────────────────┘  │
└────────┬──────────────────┬───────────────────┬──────────────────┘
         │ results are      │ dependency graph  │ runs jobs
         │ TSV / files      │ exec via CMD      │ forks processes
         ▼                  ▼                   ▼
┌────────────────────────────────────┐  ┌───────────────────────┐
│            TSV System              │  │ WorkQueue +           │
│  Parser → Dumper → Transformer →   │  │ ScoutSemaphore        │
│  Traverse (parallel via TSV.traverse│  │ (fork pools, named    │
│  class method using WorkQueue)     │  │  POSIX semaphores)    │
└────────┬───────────────────────────┘  └───────────────────────┘
         │ indexed by / stored in
         ▼
┌────────────────────────────────────┐
│     Persistence (engines)          │
│  tokyocabinet HDB/BDB, fwt,        │
│  packed_index, sharder, tkrzw      │
└────────┬───────────────────────────┘
         │ associations parsed from TSV, indexed via Persist
         ▼
┌────────────────────────────────────┐
│  Association / KnowledgeBase       │
│  (AssociationItem, Traverser rules)│
└────────┬───────────────────────────┘
         │ association items expose Entity properties
         ▼
┌────────────────────────────────────┐
│         Entity System              │
│  (Annotation-based properties,     │
│   identifier translation)          │
└────────────────────────────────────┘
```

## Relationship to scout-essentials

All subsystems rest on
[scout-essentials](https://github.com/mikisvaz/scout-essentials), which
provides the core primitives:

- **Annotation** — attaching metadata to plain Ruby objects (used by TSV,
  Step, Task, Entity)
- **Persist** — generic `Persist.persist`, `Persist.memory`, path
  conventions (`Persist.cache_dir`), save/load driver registries
- **Paths** — `Path` resolution, resource discovery, `find`
- **Streams** — `ConcurrentStream`, pipes, `Open.sensible_write`
- **Commands** — `CMD`, `Open`, `Log`, `Scout::Config`, exceptions

Scout-gear *adds* the workflow engine, the TSV data system with its
persistence adapters, the association/KnowledgeBase layer, the entity
system, WorkQueue/ScoutSemaphore, and the `scout` CLI.

The dependency direction is one-way: scout-gear requires
scout-essentials; nothing in scout-essentials requires scout-gear.

## Subsystem responsibilities

### Workflow Engine

- **Responsibility**: define computational pipelines as dependency
  graphs and execute them.
- **Key files**: `lib/scout/workflow.rb`, `lib/scout/workflow/task.rb`,
  `lib/scout/workflow/step.rb`, `lib/scout/workflow/step/`,
  `lib/scout/workflow/deployment/`.
- **Provides**: task DSL (`input`, `task`, `dep`, `helper`,
  `include_workflow`), Step lifecycle (`produce`, `run`, `join`),
  dependency resolution, provenance, HPC deployment.
- **Depends on**: `CMD` for job execution (scout-essentials);
  `ConcurrentStream` for streamed results (`step.rb:265`);
  `Persist.memory` for job memoization (`workflow.rb:171`). The engine
  core does **not** use WorkQueue — parallelism there is per-dependency
  exec/processes; WorkQueue is used by `TSV.traverse` (`tsv/open.rb:92`).
- **See**: [Workflow Engine](WorkflowEngine.md)

### TSV System

- **Responsibility**: parse, transform, and persist tabular data.
- **Key files**: `lib/scout/tsv.rb`, all files under `lib/scout/tsv/`.
- **Provides**: Parser, Dumper, Transformer, class-level
  `TSV.traverse` (parallelism), indexing, identifier translation,
  attach/join.
- **Depends on**: Persist engines (via `TSVAdapter`), ConcurrentStream
  (for streaming), WorkQueue (only from `TSV.traverse(cpus:)`).
- **See**: [TSV Internals](TSVInternals.md)

### Entity System

- **Responsibility**: attach types and properties to identifiers.
- **Key files**: `lib/scout/entity.rb`, `lib/scout/entity/`.
- **Provides**: property dispatch, format registry, identifier
  translation, annotation persistence.
- **Depends on**: Annotation (scout-essentials), TSV (identifier files
  and data loading), Persist (property caches).
- **See**: [Entity System](EntitySystem.md)

### Association / KnowledgeBase

- **Responsibility**: represent and query relationships between
  entities.
- **Key files**: `lib/scout/association.rb`, `lib/scout/knowledge_base.rb`.
- **Provides**: association parsing/indexing, KnowledgeBase registry,
  `traverse` over association items.
- **Artifacts**: registration is lazy — `kb.register` only records
  `[file, options]`; the first `get_index`/query builds two separate
  artifacts under the kb dir: the pair-keyed index
  (`<name>`, `type: :list` in a `TokyoCabinet::BDB`) and the database
  (`<name>.database`, `type: :double`), plus a reverse index
  (`<name>.reverse`) on the first `parents` query. The storage engine is
  fixed to BDB; the `:persist` option does not select it.
- **Depends on**: TSV (association data), Persist (index storage),
  Entity (properties on items). **Association depends on Entity, not the
  other way around** (`association.rb:1` requires TSV;
  association items extend entities).
- **Association Item**: the bridge object returned by KnowledgeBase
  queries; each item is annotated with its entity types so entity
  properties are available on it.
- **See**: [Entity System](EntitySystem.md),
  [Managing Relationships](../user/ManagingRelationships.md)

### Persistence (engines)

- **Responsibility**: provide multiple storage engines behind one API.
- **Key files**: `lib/scout/persist/engine.rb`,
  `lib/scout/persist/engine/*.rb`, `lib/scout/persist/tsv.rb`,
  `lib/scout/persist/tsv/adapter/*.rb`.
- **Provides**: TokyoCabinet HDB/BDB (plus `:big` variant), FixWidthTable
  (`fwt`), PackedIndex (`pki`), Sharder, TSVAdapter (Tkrzw code is
  dormant)
  (TSV view over a database), serializers.
- **Depends on**: the `tokyocabinet` gem and
  `tokyocabinet-utils` CLI tools (`CMD.cmd("hdb importtsv …")`,
  `engine/tokyocabinet.rb:134`) for streaming import; on scout-essentials
  for `Persist.persist`, path resolution, and driver registries.
- **See**: [Persistence Engines](PersistenceEngines.md)

### Concurrency (WorkQueue, ScoutSemaphore)

- **Responsibility**: multi-process parallelism and synchronization.
- **Key files**: `lib/scout/work_queue.rb` (+ `socket.rb`, `worker.rb`,
  `exceptions.rb`), `lib/scout/semaphore.rb`, and the read-only
  `lib/scout/monitor.rb` (see below).
- **WorkQueue**: fork-based worker pool with socket IPC; used by
  `TSV.traverse(cpus:)`.
- **ScoutSemaphore**: named POSIX semaphores built with RubyInline
  (`/dev/shm/sem.scout*`); fails loudly when the C extension cannot
  compile (no silent no-op).
- **See**: [Concurrency Model](ConcurrencyModel.md),
  [Running Parallel Work](../user/RunningParallelWork.md)
- **Monitor** (`lib/scout/monitor.rb`): not a concurrency primitive but a
  read-only *introspection* helper for `scout system status`/`clean`. It
  never takes locks: `Scout.locks/lock_info`, `sensiblewrites/…_info`,
  `persists/…_info`, `job_info`, `file_time`, `load_lock` and `dump_memory`
  shell out to `find -L` over the lock/persist/job directory constants
  (`LOCK_DIRS`, `PERSIST_DIRS`, `JOB_DIRS`, `SENSIBLE_WRITE_DIRS`) and parse
  what they find. It is loaded explicitly by
  `scout_commands/system/{status,clean}` — `require 'scout'` alone does not
  define the `Scout.lock_*` methods.

## Module dependency graph

Derived from `require` statements:

```
workflow ─→ scout-essentials (resource, persist, streams, cmd, config)
workflow ─→ tsv
tsv ─→ persist (engines + TSVAdapter)
tsv ─→ work_queue        (only for class-level TSV.traverse with cpus)
tsv ─→ association ─→ entity
association ─→ tsv
knowledge_base ─→ association + entity + persist
entity ─→ annotation (essentials), tsv, persist
persist engines ─→ tokyocabinet gem, tokyocabinet-utils CLI (CMD)
work_queue ─→ scout-essentials (socket/fork helpers)
semaphore ─→ RubyInline (C extension at runtime)
```

Notable corrections to older diagrams:

- **Entity does not depend on Association** — the edge runs the other way
  (`association.rb` requires entity).
- **The workflow engine core does not use WorkQueue**; only
  `TSV.traverse(cpus:)` does.
- **Deployment includes local and queue dispatch**, not only
  SLURM/PBS/LSF (`deployment/local.rb`, `deployment/queue.rb`,
  `deployment/scheduler/`).

## Key design decisions

1. **Annotation-based extensibility**: TSV, Entity, Step, and Task are
   plain Ruby objects (a TSV *is* a Hash) extended with modules rather
   than subclassed. This is the fundamental Scout pattern. See
   [Design Principles](DesignPrinciples.md).

2. **Streaming-first data movement**: TSV operations (traverse, attach,
   reorder) move data through pipes and threads instead of building
   intermediate arrays, which keeps memory bounded on large files.

3. **Results as files, cached by convention**: every workflow job result
   lives under `var/jobs/...` (configurable via
   `Scout::Config.get(:directory, :workflow_jobs, :workflow, :jobs)`),
   so re-running a job reuses its previous result; `Persist` engines
   cache expensive indexes and transformations on top of that.

4. **Convention over configuration in paths**: persisted data, job
   results, and identifier files follow derived path conventions, so
   callers rarely specify paths explicitly.

5. **Fork-based parallelism**: CPU parallelism uses process forking
   (WorkQueue) rather than threads, avoiding GVL contention and giving
   each worker independent memory. Coordination is by IPC sockets
   (each socket a pair of named semaphores, for frame atomicity); the
   semaphore consumer list in-tree is small — WorkQueue sockets, the
   WorkQueue abort path, and the optional `Step#fork(noload, semaphore)`
   wrapper (`workflow/step.rb:291`), which no in-repo caller currently
   passes. Deployment resource limits are enforced by the local
   executor's `check_resources` bookkeeping
   (`workflow/deployment/local.rb:202-224`), not by semaphores.

## See also

- [Start Here](../StartHere.md)
- [Design Principles](DesignPrinciples.md)
- [Repository map](../../research/repo-map.md)
