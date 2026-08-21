# Scout Gear

**Workflows, data, entities and persistence for the Scout ecosystem.**

Scout turns computation into persistent, composable, inspectable work.
Scout-gear is the workflow and data-processing layer of the Scout
ecosystem: it provides a workflow engine for computational pipelines, a
tabular data system (TSV), an entity system for typed identifiers, a
knowledge base for relationship queries, and specialized persistence
engines. It builds on
[scout-essentials](https://github.com/mikisvaz/scout-essentials), which
provides the foundational utilities (file I/O, annotations, paths,
logging, concurrency streams).

New to Scout? Start with [StartHere](doc/StartHere.md) for an
audience-oriented route into the documentation.

## The Scout model

In scout-gear a task is not a transient function call. Running a job
creates a **Step**: a concrete unit of work with typed inputs, declared
dependencies, and a unique path derived from those inputs. Because the
path identifies the work, the result is written to disk, reused on
re-run, and only recomputed when the inputs change. Everything that
happened to produce it is recorded with it.

```text
task -> job (Step) -> persistent result -> provenance -> composition / orchestration
```

The canonical example:

```ruby
module Baking
  extend Workflow
  input :name, :string
  task :say => :string do |name| "Hi #{name}" end
end
Baking.job(:say, name: "Miguel").run # => "Hi Miguel"
```

From this one idea follow the properties that make workflows tractable at scale:

- **Caching** — jobs have a unique path derived from their inputs; the
  same job run twice returns the cached result without re-executing.
- **Dependencies** — the engine resolves the dependency graph, runs
  tasks in the right order, and streams results between them instead of
  materializing intermediates.
- **Provenance** — what ran, when, and with what inputs is tracked and
  inspectable on every job.
- **Orchestration** — jobs run under resource rules (multiple
  processes, bounded by semaphores) and can be deployed to HPC
  schedulers (SLURM, PBS, LSF) or containers (Singularity).

See [Building Workflows](doc/user/BuildingWorkflows.md) and the
[Workflow Engine](doc/developer/WorkflowEngine.md) internals.

## Why these subsystems belong together

The subsystems in scout-gear are not a grab bag of modules; they are one
system for making large, structured, persistent computations composable.
The workflow engine needs data that can move through pipes (TSV), data
that survives between runs (Persist), data that carries meaning
(Entity/Association/KnowledgeBase), and execution bounded by real
resources (WorkQueue/Semaphore).

| Subsystem | What it contributes |
| --- | --- |
| TSV | typed tabular data, streaming, parallel traversal, persistence, indexing |
| Entity / Association / KnowledgeBase | typed identifiers, properties, relationship indices, traversal queries |
| Persist | transparent caching of expensive computation |
| WorkQueue / Semaphore | multi-process parallelism bounded by resources |

This coherence is anchored in three design principles shared across the
codebase:

1. **Annotate, don't subclass** — attach behavior to existing objects
   (a TSV is a plain Hash, an Entity is a plain String) instead of
   creating new classes.
2. **Stream, don't load** — process data row by row through pipes
   instead of materializing datasets in memory.
3. **Persist as cache** — expensive computation is transparently cached
   and recomputed only when inputs change.

The principles are explained with idiomatic and non-idiomatic examples in
[Design Principles](doc/developer/DesignPrinciples.md).

## The Scout stack

```text
+------------------------------------------------------------+
|  scout-ai                                                  |
|  reasoning, conversations, agents                          |
+------------------------------------------------------------+
|  scout-rig / scout-camp   (optional ecosystem)             |
|  bridging other languages / remote servers, cloud, web     |
+------------------------------------------------------------+
|  scout-gear                     << THIS REPO >>            |
|  workflows, data, entities, persistence, concurrency,      |
|  knowledge, provenance                                     |
+------------------------------------------------------------+
|  scout-essentials                                          |
|  paths, IO, resources, caching, streams                    |
+------------------------------------------------------------+
```

### Scout-AI

[Scout-AI](https://github.com/mikisvaz/scout-ai) is an agent and LLM
layer built on top of Scout. It provides a reproducible conversation
format (Chat), tool calling backed by real Scout workflows, knowledge
bases and MCP servers, and multi-agent orchestration encoded as typed,
inspectable workflow jobs. In Scout-AI a tool is therefore not just an
API wrapper: it can be a real Scout workflow with steps, dependencies,
persistence and provenance. The point of scout-gear is that it is the
computational substrate AI systems operate in.

## Where to start

The entry point for all documentation is
[StartHere](doc/StartHere.md), which routes readers by intent.

### User guides

- [Building Workflows](doc/user/BuildingWorkflows.md) — define tasks,
  inputs, dependencies, and run jobs.
- [Processing Tabular Data](doc/user/ProcessingTabularData.md) — open,
  create, transform, and filter TSV data.
- [Working with Entities](doc/user/WorkingWithEntities.md) — attach
  types and properties to identifiers.
- [Managing Relationships](doc/user/ManagingRelationships.md) — build
  knowledge bases and query relationships.
- [Running Parallel Work](doc/user/RunningParallelWork.md) — distribute
  work across multiple processes.
- [Caching Data](doc/user/CachingData.md) — persist results to avoid
  redundant computation.
- [Cookbook](doc/user/Cookbook.md) — practical recipes combining
  multiple subsystems.

### Developer docs

- [Architecture](doc/developer/Architecture.md) — subsystem map and
  dependency graph.
- [Design Principles](doc/developer/DesignPrinciples.md) — coding
  philosophy and idioms.
- [Workflow Engine](doc/developer/WorkflowEngine.md) — task lifecycle,
  Step execution, dependency resolution.
- [TSV Internals](doc/developer/TSVInternals.md) — parser/dumper/
  transformer pipeline, traverse, indexing.
- [Entity System](doc/developer/EntitySystem.md) — property dispatch,
  format registry, KnowledgeBase traversal.
- [Persistence Engines](doc/developer/PersistenceEngines.md) — database
  engines and the TSVAdapter pattern.
- [Concurrency Model](doc/developer/ConcurrencyModel.md) — WorkQueue
  fork+IPC and Semaphore synchronization.

### Improvements and research

- [Improvements](doc/Improvements.md) — prioritized, actionable
  recommendations for code and architecture.
- [Research artifacts](research/) — non-normative investigation
  documents recording code-level detail and design reasoning; useful
  background, but not the specification.

## Install

Scout-gear is published as the `scout-gear` gem and installs a single
`scout` executable:

```sh
gem install scout-gear
```

The `scout` command discovers subcommands contributed by installed Scout
packages, so the set of commands grows with what you have installed. A
good pointer into the workflow tooling is:

```sh
scout workflow
```

## Ecosystem and lineage

- [scout-essentials](https://github.com/mikisvaz/scout-essentials) —
  foundational utilities: paths, IO, resources, caching, streams.
- [scout-camp](https://github.com/mikisvaz/scout-camp) — remote
  servers, cloud deployments, web interfaces, cross-site operations.
- [scout-rig](https://github.com/mikisvaz/scout-rig) — bridge to other
  languages (for example Python).
- [scout-ai](https://github.com/mikisvaz/scout-ai) — agents, LLMs and
  tool calling on top of Scout.

Many of Scout's ideas and utilities originated in
[Rbbt](https://github.com/Rbbt-Workflows), which still carries many
real-world workflow examples.

## License

MIT — see [LICENSE.txt](LICENSE.txt) (Copyright (c) 2023 Miguel
Vazquez).
