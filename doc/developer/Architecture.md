# Architecture

This document provides a high-level map of scout-gear's subsystems, their
responsibilities, and how they interact.

It is intended for framework contributors who need to understand the overall
structure before diving into specific subsystems.

## Subsystem map

```
┌─────────────────────────────────────────────────────────────┐
│                       Workflow Engine                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐      │
│  │  Task    │──│  Step    │──│  Deployment           │      │
│  │  (DSL)   │  │ (exec)   │  │  (SLURM/PBS/LSF)      │      │
│  └──────────┘  └──────────┘  └──────────────────────┘      │
│       │              │                                       │
│       │              │ depends on                            │
│       ▼              ▼                                       │
│  ┌──────────────────────────┐                               │
│  │      TSV System           │                               │
│  │  Parser → Dumper →       │                               │
│  │  Transformer → Traverse   │                               │
│  └──────────────────────────┘                               │
│       │                                                      │
│       │ persists via                                         │
│       ▼                                                      │
│  ┌──────────────────────────┐                               │
│  │    Persistence Layer      │                               │
│  │  (HDB/BDB/FWT/Sharder)    │               ┌──────────┐  │
│  └──────────────────────────┘               │WorkQueue │  │
│       │                                      │Semaphore │  │
│       │ indexes support                      └──────────┘  │
│       ▼               │                                     │
│  ┌──────────────────────────┐               │               │
│  │   Association / KB        │───────────────┘               │
│  │  (Traverser, Indexes)     │                               │
│  └──────────────────────────┘                               │
│       │                                                      │
│       │ entity properties                                   │
│       ▼                                                      │
│  ┌──────────────────────────┐                               │
│  │      Entity System        │                               │
│  │  (Annotation, Format)     │                               │
│  └──────────────────────────┘                               │
└─────────────────────────────────────────────────────────────┘
```

All subsystems rest on [scout-essentials](https://https://github.com/mikisvaz/scout-essentials),
which provides:
- [Annotation](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/AnnotationSystem.md) — annotation-based extensibility
- [Persistence](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/PersistenceAndResources.md) — basic caching, path conventions
- [Paths](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/PathResolution.md) — path resolution, resource discovery
- [Streams](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/StreamingModel.md) — ConcurrentStream, pipes
- [Commands](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/Architecture.md) — CMD, Log

## Subsystem responsibilities

### Workflow Engine
- **Responsibility**: Define computational pipelines as dependency graphs.
- **Key files**: `lib/scout/workflow.rb`, `lib/scout/workflow/task.rb`,
  `lib/scout/workflow/step.rb`, `lib/scout/workflow/deployment/`
- **Provides**: Task DSL, Step lifecycle, dependency resolution,
  provenance, deployment to HPC schedulers.
- **Depends on**: TSV (as result type), Persist (for result caching),
  WorkQueue (for parallel dependency execution).
- **See**: [Workflow Engine](WorkflowEngine.md)

### TSV System
- **Responsibility**: Parse, transform, and persist tabular data.
- `lib/scout/tsv.rb`, all files under `lib/scout/tsv/`
- **Provides**: Parser, Dumper, Transformer, traverse, indexing,
  identifier translation, attach/join.
- **Depends on**: Persist (for persistent databases), ConcurrentStream
  (for streaming).
- **See**: [TSV Internals](TSVInternals.md)

### Entity System
- **Responsibility**: Attach types and properties to identifiers.
- **Key files**: `lib/scout/entity.rb`
- **Provides**: Property dispatch, format registry, identifier
  translation.
- **Depends on**: Annotation (from scout-essentials), TSV (for loading
  data into properties).
- **See**: [Entity System](EntitySystem.md)

### Association / KnowledgeBase
- **Responsibility**: Represent and query relationships between entities.
- **Key files**: `lib/scout/association.rb`, `lib/scout/knowledge_base.rb`
- **Provides**: Association indexing, KnowledgeBase registry, Traverser
  for graph traversal.
- **Depends on**: Entity (for property integration), TSV (for parsing
  association data), Persist (for index persistence).
- **Association Item**: Bridge between Association and Entity. Each
  relationship is an AssociationItem.
- **See**: [Entity System](EntitySystem.md)

### Persistence Layer
- **Responsibility**: Provide multiple storage engines with a unified API.
- **Key files**: `lib/scout/persist.rb`, all files under `lib/scout/persist/`
- **Provides**: HDB, BDB, Tkrzw, FixWidthTable, PackedIndex, Sharder,
  TSVAdapter (serialization).
- **Depends on**: TSV (for serialization format), CMD (for invoking
  external tools like tokyocabinet-utils).
- **See**: [Persistence Engines](PersistenceEngines.md)

### Concurrency (WorkQueue, Semaphore)
- **Responsibility**: Multi-process parallelism and synchronization.
- **Key files**: `-level/scout/work_queue.rb`, `lib/scout/semaphore.rb`
- **WorkQueue**: Fork-based parallel processing with IPC sockets.
- **Semaphore**: File-based synchronization using C extensions.
- **See**: [Concurrency Model](ConcurrencyModel.md)

## Module dependency graph

```
Workflow ──depends on──> TSV ──depends on──> Persist ──depends on──> scout-essentials
   │                        │                    │
   │                        │                    └──> Tkrzw, TokyoCabinet
   │                        │
   │                        └──depends on──> Entity
   │                                          │
   │                                          └──depends on──> Association ──> KnowledgeBase
   │
   └──depends on──> WorkQueue ──depends on──> scout-essentials (ConcurrentStream)
```

## Key design decisions

1. **Annotation-based extensibility**: TSV, Entity, Step, and Task all use
   scout-essentials' Annotation module to attach metadata to plain Ruby
   objects (Hashes, Strings, Strings) without subclassing. This is the
   fundamental Scout pattern. See [Design Principles](DesignPrinciples.md).

2. **Streaming-first**: TSV operations (traverse, attach, reorder) use
   pipes and threads, not recursion, to move data. This avoids stack
   overflows and deadlocks when chaining multiple streaming operations.

3. **Persistence as caching**: Persistence is not just about saving data;
   it's an integral part of the workflow model. Every workflow result is
   persisted, and persistence is used to cache expensive computations like
   indexes and transformations.

4. **Convention over configuration in paths**: Persisted data, job results,
   and identifier files follow path conventions that eliminate the need for
   explicit configuration. The path is derived from the inputs and the
   operation type.

5. **Fork-based parallelism**: Instead of threading, scout-gear uses
   process forking for CPU parallelism. This avoids GIL issues and gives
   each worker an independent memory space. WorkQueue manages the IPC.

## See also

- [scout-overview README](../StartHere.md)
- [Design Principles](DesignPrinciples.md)
- [Research artifacts](../../research/)
