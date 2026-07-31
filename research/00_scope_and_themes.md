# Investigation: Scope and Themes

> **Non-normative.** This document is a working investigation. It may contain
> implementation details, code exploration notes, and hypotheses. Refer to
> `doc/developer/` for maintained architectural documentation.

## Repository overview

**scout-gear** is the workflow and data-processing layer of the Scout
ecosystem. It builds on **scout-essentials** (file I/O, annotations,
persistence, logging, paths, concurrency streams) and provides:

- A **workflow engine** for defining, executing, and managing computational
  pipelines with dependency resolution, provenance, and deployment to
  local, SLURM, PBS, LFS, and Singularity environments.
- A **tabular data system** (TSV) for parsing, transforming, indexing, and
  streaming structured data with type-aware operations.
- An **entity system** for attaching metadata and type information to
  identifiers and translating between identifier formats.
- An **association and knowledge-base system** for representing and querying
  relationships between entities.
- **Persistence engines** (TokyoCabinet, Tkrzw, FixWidthTable, PackedIndex,
  Sharder) for on-disk key-value storage of TSV data.
- **Concurrency primitives** (WorkQueue for multi-process parallelism,
  Semaphore for POSIX semaphore-based synchronization).

## Source structure

```
lib/scout/
├── workflow.rb              # Workflow module: task definition DSL, job creation
├── tsv.rb                   # TSV module: tabular data, the central data structure
├── entity.rb                # Entity module: typed identifiers with properties
├── association.rb           # Association module: relationship representation
├── knowledge_base.rb        # KnowledgeBase: registry + query engine for associations
├── work_queue.rb            # WorkQueue: multi-process parallelism via fork + IPC
├── semaphore.rb             # ScoutSemaphore: POSIX named semaphores (RubyInline C)
├── monitor.rb               # Monitor: job execution monitoring
├── workflow/                # Workflow engine internals
│   ├── definition.rb        # Task/input/dep/helper/semaphore DSL
│   ├── task.rb              # Task annotation + job creation logic
│   ├── step.rb              # Step: execution unit, lifecycle, persistence
│   ├── documentation.rb     # Auto-generated workflow docs
│   ├── util.rb              # Workflow utilities (job finding, etc.)
│   ├── step/                # Step sub-behaviors
│   │   ├── info.rb          # Info file (provenance metadata)
│   │   ├── status.rb        # Status checking (done, error, etc.)
│   │   ├── load.rb          # Loading results from disk
│   │   ├── file.rb          # File management (files_dir, etc.)
│   │   ├── dependencies.rb  # Dependency resolution and execution
│   │   ├── provenance.rb    # Provenance extraction
│   │   ├── config.rb        # Configuration management
│   │   ├── progress.rb      # Progress tracking
│   │   ├── inputs.rb        # Input formatting
│   │   ├── children.rb      # Child step management
│   │   └── archive.rb       # Archiving
│   ├── task/
│   │   ├── inputs.rb        # Input processing
│   │   ├── dependencies.rb  # Dependency specification DSL
│   │   └── info.rb          # Task info
│   └── deployment/          # Deployment strategies
│       ├── deploy.rb        # Deployment abstraction
│       ├── singularity.rb   # Singularity image execution
│       ├── scheduler.rb     # Scheduler abstraction
│       └── scheduler/       # HPC schedulers
│           ├── slurm.rb
│           ├── pbs.rb
│           └── lfs.rb
├── tsv/                     # TSV internals
│   ├── parser.rb            # TSV parsing pipeline (header, parse_line, parse_stream)
│   ├── dumper.rb            # TSV output/streaming
│   ├── transformer.rb       # Transformer: streaming pipeline abstraction
│   ├── traverse.rb          # Traverse: row iteration + type conversion
│   ├── index.rb             # Point/range index building
│   ├── attach.rb            # Attach/join operations
│   ├── change_id.rb         # Identifier translation
│   ├── open.rb              # TSV.open with persistence
│   ├── stream.rb            # Streaming operations
│   ├── annotation.rb        # TSV annotation integration
│   ├── path.rb              # Path integration
│   ├── csv.rb               # CSV support
│   └── util.rb              # Utilities
├── entity/                  # Entity internals
│   ├── format.rb            # Format registry and translation
│   ├── property.rb          # Property type system (:single, :array, etc.)
│   ├── object.rb            # Entity instance methods
│   ├── identifiers.rb       # Identifier file handling
│   └── named_array.rb       # NamedArray integration
├── association/             # Association internals
│   ├── fields.rb            # Source/target field specification
│   ├── util.rb              # Association utilities
│   ├── index.rb             # Association index/database building
│   └── item.rb              # AssociationItem: entity for association rows
├── knowledge_base/          # KB internals
│   ├── registry.rb          # Association registration
│   ├── query.rb             # Query API
│   ├── traverse.rb          # Graph traversal DSL
│   ├── list.rb              # List operations
│   ├── entity.rb            # Entity integration
│   └── description.rb       # KB description/config
└── persist/                 # Persistence engines
    ├── engine.rb            # Engine loader
    ├── tsv.rb               # Persist.tsv: TSV-aware persistence
    ├── tsv/
    │   ├── adapter.rb       # TSVAdapter: annotation + serialization
    │   ├── adapter/         # Engine-specific adapters
    │   │   ├── base.rb      # Base adapter: locking, annotation, serialization
    │   │   ├── tokyocabinet.rb
    │   │   ├── fix_width_table.rb
    │   │   ├── packed_index.rb
    │   │   ├── sharder.rb
    │   │   └── tkrzw.rb
    │   └── serialize.rb     # Serializer definitions
    └── engine/              # Low-level engines
        ├── tokyocabinet.rb  # HDB/BDB via tc/tdb
        ├── fix_width_table.rb # Fixed-width value table
        ├── packed_index.rb  # Compact positional index
        ├── sharder.rb       # Sharding across multiple databases
        └── tkrzw.rb         # Tkrzw engine (optional)
```

## Investigation themes

1. **Workflow engine** — Task definition DSL, Step lifecycle, dependency
   resolution, deployment, provenance, streaming, persistence, documentation.
2. **TSV internals** — Data model (4 types), parsing pipeline, Dumper/Transformer
   streaming, traverse abstraction, indexing, identifier translation, attach/join.
3. **Entity and Association systems** — Property dispatch, format translation,
   Association indexing, KnowledgeBase query/traversal.
4. **Persistence engines and concurrency** — TokyoCabinet, FixWidthTable,
   PackedIndex, Sharder, TSVAdapter pattern, WorkQueue, Semaphore.
5. **Design philosophy and coding conventions** — Annotation-based
   extensibility, streaming-first architecture, convention-over-configuration.

## Cross-references to scout-essentials

The following concepts are documented in scout-essentials and should be
cross-referenced rather than re-explained:

- **Annotations** (the `Annotation` module that TSV, Entity, Task, Step all use)
- **Basic persistence** (`Persist.persist`, caching patterns)
- **File I/O** (`Open` module)
- **Path resolution** (`Path` module)
- **Logging** (`Log` module)
- **NamedArray** and **IndiferentHash**
- **ConcurrentStream** (the streaming protocol)
- **TmpFile** and **Resource**

scout-essentials docs on GitHub:
`https://github.com/mikisvaz/scout-essentials/blob/main/doc/`
