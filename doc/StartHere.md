# Scout-Gear Documentation

Scout-gear is the workflow and data-processing layer of the Scout
ecosystem. It provides a workflow engine for building computational
pipelines, a tabular data system (TSV) for structured data, an entity
system for typed identifiers, a knowledge base for relationship queries,
specialized persistence engines, and HPC batch deployment.

It builds on [scout-essentials](https://github.com/mikisvaz/scout-essentials),
which provides the foundational utilities (file I/O, annotations, paths,
logging, concurrency streams, `Persist.persist` itself).

## Which documentation should I read?

### I want to build applications using scout-gear

→ Read the **[User Documentation](user/)**

The user docs are concept-oriented guides that teach you how to use the
library to solve problems. They are organized around tasks, not classes.

**Start here:**
- [Building Workflows](user/BuildingWorkflows.md) — Define tasks, inputs, dependencies, and run jobs.
- [Processing Tabular Data](user/ProcessingTabularData.md) — Open, create, transform, and filter TSV data.
- [Working with Entities](user/WorkingWithEntities.md) — Attach types and properties to identifiers.
- [Managing Relationships](user/ManagingRelationships.md) — Build knowledge bases and query relationships.
- [Running Parallel Work](user/RunningParallelWork.md) — Distribute work across multiple processes.
- [Caching Data](user/CachingData.md) — Persist results to avoid redundant computation.
- [Using the CLI](user/UsingTheCLI.md) — The `scout` executable: dispatch, options, help, exit codes.
- [HPC / Batch Execution](user/HPCBatchExecution.md) — Run jobs on SLURM/PBS/LSF clusters.
- [Cookbook](user/Cookbook.md) — Practical recipes combining multiple subsystems.

### I want to understand how scout-gear is implemented

→ Read the **[Developer Documentation](developer/)**

The developer docs explain the internal architecture, key abstractions,
and design decisions behind the framework.

**Start here:**
- [Architecture](developer/Architecture.md) — Subsystem map and dependency graph.
- [Design Principles](developer/DesignPrinciples.md) — Coding philosophy and idioms.
- [Workflow Engine](developer/WorkflowEngine.md) — Task lifecycle, Step execution, dependency resolution.
- [TSV Internals](developer/TSVInternals.md) — Parser/Dumper/Transformer pipeline, traverse, indexing.
- [Entity System](developer/EntitySystem.md) — Property dispatch, format registry, KnowledgeBase traversal.
- [Persistence Engines](developer/PersistenceEngines.md) — Database engines and the TSVAdapter pattern.
- [Concurrency Model](developer/ConcurrencyModel.md) — WorkQueue fork+IPC and ScoutSemaphore synchronization.

### I want to see detailed architectural investigations

→ Read the **[Research Artifacts](../research/)**

These are working investigation documents with code-level detail,
warnings, and design observations. They are **non-normative** — they
preserve the reasoning behind design decisions but may become outdated.
Consult them when you need to understand how a subsystem actually works
at the implementation level.

### I want to see recommended improvements

→ Read **[Improvements.md](Improvements.md)**

A list of actionable recommendations for code improvements, bug fixes,
and architectural refinements discovered during the documentation effort.

### I want to run workflows from the command line

→ Read **[Using the CLI](user/UsingTheCLI.md)**

The `scout` executable (`scout_commands/`) exposes workflow execution
(`scout workflow`), batch management (`scout batch`), and utilities;
[Using the CLI](user/UsingTheCLI.md) documents the dispatcher, the
option convention every command shares, and the exit codes. For batch
submission on a cluster, continue to
[HPC / Batch Execution](user/HPCBatchExecution.md).
