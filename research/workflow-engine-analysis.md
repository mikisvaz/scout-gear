# Investigation: Workflow Engine

> **Non-normative.** Working investigation with implementation details.

## Overview

The Workflow engine is scout-gear's flagship subsystem. It provides a DSL for
defining computational pipelines as graphs of **tasks**, with automatic
dependency resolution, result persistence, provenance tracking, streaming, and
deployment to local or HPC environments (SLURM, PBS, LFS, Singularity).

## Key classes and roles

### `Workflow` module (`lib/scout/workflow/definition.rb`)

Extended via `Annotation` — it carries `name`, `tasks`, `helpers` as annotations.

**DSL methods** (used at the class/module level of a workflow definition):

| Method | Purpose |
|--------|---------|
| `input(name, type, *desc)` | Declare an input for the next task |
| `desc(description)` | Set the description for the next task |
| `returns(type)` | Declare the return type for the next task |
| `extension(ext)` | Set file extension for the next task |
| `dep(workflow, task, options, &block)` | Declare a dependency for the next task |
| `task(name => type, &block)` | Define a task (creates a `Task` annotation) |
| `task_alias(name, workflow, oname, ...)` | Create a pass-through task wrapping a dependency |
| `helper(name, &block)` | Define a helper method available in task bodies |
| `include_workflow(workflow)` | Merge another workflow's tasks and helpers |

**`annotate_next_task` pattern**: The DSL uses a deferred-annotation pattern.
Calls to `input`, `desc`, `returns`, `dep` etc. accumulate in
`@annotate_next_task`. When `task` is called, it consumes these accumulated
annotations, creates the `Task` object, then resets the accumulator. This is the
idiomatic Scout approach to building a fluent DSL.

### `Task` (`lib/scout/workflow/task.rb`)

An `Annotation` wrapping a block. Key annotations: `name`, `type`, `inputs`,
`deps`, `description`, `directory`, `workflow`.

- **`job(*args)`** — Creates a `Step` from the task, resolving inputs and
  dependencies.
- **`alias?`** — Returns true for pass-through tasks (`extension == :dep_task`).

### `Step` (`lib/scout/workflow/step.rb`)

The **execution unit**. A Step represents one concrete job instance with a
specific set of inputs and a unique path.

**Lifecycle:**

1. **Creation** — `Task#job` builds the Step with a unique path derived from
   inputs, inputs list, and dependencies. The path is a directory under
   `Workflow#directory` → `var/jobs/<workflow>/<task>/<digest>.<ext>`.

2. **Resolution** — Dependencies are resolved recursively. Each dependency is
   itself a Step. The `dependencies` method (in `task/dependencies.rb`) handles:
   - **Direct dependencies** (`dep` declarations)
   - **Dynamic dependencies** (block-based `dep` calls that return Step, Hash, or Array)
   - **Overriden dependencies** (`provided_inputs` with `Workflow#Task` keys)
   - **Input dependencies** (Steps passed as inputs)

3. **Execution** — `run(stream)`:
   - Checks if done (path exists) → loads result
   - Calls `prepare_dependencies` (cleans outdated deps, raises on errors)
   - Calls `run_dependencies` (starts each dependency, optionally streaming)
   - Calls `exec` (runs the task block in the Step's `exec_context`)
   - Result is persisted via `Persist.persist` with locking
   - If result is an IO/StringIO, sets up streaming callbacks

4. **Streaming** — When `stream=true`, the task block returns an IO stream
   that is passed directly to the parent without writing to disk first.
   The `ConcurrentStream` protocol handles callback-based completion.

5. **Completion** — On success, `merge_info(:status => :done, :end => Time.now)`.
   On error, exception is encoded and stored in the info file.

**Key methods:**

| Method | Purpose |
|--------|---------|
| `run(stream=false)` | Execute the step (with optional streaming) |
| `exec` | Run the task block directly (no persistence) |
| `load` | Load the persisted result from disk |
| `join` | Block until step completes; consumes streams |
| `produce(with_fork:)` | Ensure step is produced (optionally via fork) |
| `fork(noload, semaphore)` | Execute in a forked process |
| `done?` | Check if result file exists |
| `stream` | Get the result stream (for streaming steps) |
| `clean` | Remove all files for this step |
| `updated?` | Check if result is newer than all dependencies |
| `info` | Load the info hash from the info file |
| `merge_info(hash)` | Merge info and persist to info file |

### Step Info / Provenance (`step/info.rb`)

Each Step has a `.info` sidecar file (serialized as JSON by default) containing:
- `status`: `:waiting`, `:setup`, `:start`, `:streaming`, `:done`, `:error`, `:aborted`, `:cleaned`
- `issued`, `start`, `end`: timestamps
- `pid`, `pid_hostname`: execution process info
- `task_name`, `workflow`: task identification
- `inputs`, `input_names`: serialized inputs
- `dependencies`: list of dependency paths
- `exception`: serialized exception (JSON with `create_additions`)
- `messages`: log messages
- `time_elapsed`, `total_time_elapsed`

### Dependency Resolution (`step/dependencies.rb`, `task/dependencies.rb`)

**`Task#dependencies`** (`task/dependencies.rb`):
The core dependency resolution algorithm. For each declared dependency:
1. Check for overrides (when `provided_inputs` contains `"Workflow#task"` key)
2. If the dependency has a block, call it to get dynamic dependency specifications
3. Resolve `Symbol` input references to previously-resolved dependencies
4. Create `Step` objects for each dependency via `workflow.job`

**`Step#run_dependencies`** (`step/dependencies.rb`):
Runs all dependencies. Key features:
- Respects `compute` options per dependency (`:stream`, `:produce`, `:canfail`, `false`)
- Streaming is the default (unless `SCOUT_EXPLICIT_STREAMING=true`)
- Dependencies run in parallel (each `dep.run(stream)` starts execution)

**Override system**: Dependencies can be overridden by passing a Step or path
in `provided_inputs` under the key `"Workflow#task"`. The overriden step is
marked and gets `overriden_task` / `overriden_workflow` attributes.

### Deployment / HPC (`workflow/deployment/`)

**Architecture:**

```
Workflow::Scheduler.produce(jobs, rules)
    ↓
Workflow::Orchestrator.job_batches(rules, jobs)
    ↓ (groups jobs into batches, applies rules, builds dependency chains)
Workflow::Scheduler.process_batches(batches)
    ↓ (dispatches to the appropriate scheduler)
SLURM / PBS / LSF.run_job(job, options)
    ↓ (generates batch script, submits to queue)
```

**`SchedulerJob` module** (`deployment/scheduler/job.rb`): Shared logic for all
schedulers. Generates batch scripts with:
- Header (scheduler-specific directives)
- Environment preparation (modules, conda, container setup)
- Execution (the actual `scout workflow task` command)
- Sync (rsync results from container)
- Cleanup (container wipe, dep purge)
- Exit status tracking

**Orchestrator** (`deployment/orchestrator/`):
- `rules.rb` — Rule accumulation, merging, task-specific rules
- `batches.rb` — Groups jobs into batches, adds dependency edges
- `chains.rb` — Parses chain definitions (jobs that can be run together)
- `workload.rb` — Computes the workload (all jobs + their dependencies)

**Singularity integration**: Container execution with bind mounts, hardened
containers, and result synchronization.

### `task_alias` / `dep_task` pattern

A common pattern: a task that simply wraps a dependency. The task body waits
for the dependency, then either links the result or copies the files_dir.
Configurable via `:forget_task_alias` (removes dependency after completion)
and `:remove_dep_tasks` (cleans up dependency files).

## File layout on disk

```
var/jobs/
└── <Workflow>/
    └── <task>/
        ├── <digest>.<ext>        # Result file
        ├── <digest>.<ext>.info   # Info/provenance (JSON)
        └── <digest>.<ext>.files/ # Auxiliary files directory
```

## Design observations

1. **Annotation-based extensibility** — Both Workflow and Task use the
   Annotation module from scout-essentials. This means metadata (name, inputs,
   deps, etc.) is stored as annotations on the objects themselves.

2. **Convention-over-configuration paths** — Paths are derived from workflow
   name, task name, and input digests. No explicit path configuration needed.

3. **Streaming-first** — Results can be streamed directly between steps without
   intermediate disk writes. This is controlled by the `compute` options and the
   `stream` parameter of `run`.

4. **Fork-based parallelism** — Steps can fork into separate processes via
   `Process.fork`. This is used both for streaming and for semaphore-controlled
   parallel execution.

5. **Info files as provenance** — The `.info` sidecar file is the single source
   of truth for a step's state. It's read on demand and cached with mtime checks.

6. **`Persist.persist` as execution wrapper** — The actual task execution happens
   inside a `Persist.persist` block, which provides locking, caching, and
   tmp-file-then-atomic-move semantics.

## Warnings

- `Step#fork` uses `Process.fork` and `exit!` which skips Ruby at_exit handlers.
  This is intentional for performance but means finalizers don't run in forked
  processes.
- The `@info` caching uses mtime comparison which can race if the info file is
  written from another process (e.g., a streaming dependency).
- `task_alias` cleanup logic is complex and has many config-dependent branches.
  The `REMOVE_TASK_ALIAS` environment variable behavior is subtle.
- The `cleaned_dependencies` method always returns `[]` (dead code).
