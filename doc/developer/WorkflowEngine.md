# Workflow Engine

This document describes the architecture of the Workflow engine.

It is intended for framework contributors who need to understand or extend
the workflow system.

## Overview

The Workflow engine provides a Ruby DSL for defining computational
pipelines as dependency graphs. A workflow is a module that extends
`Workflow`. Tasks are defined with a declarative DSL and executed as Steps
with automatic dependency resolution, caching, and provenance tracking.

## Key classes and files

| Component | File | Role |
|-----------|------|------|
| `Workflow` (module) | `lib/scout/workflow.rb`, `lib/scout/workflow/definition.rb` | DSL context: `input`, `task`, `dep`, `helper`, `returns`, `extension` |
| `Task` (module) | `lib/scout/workflow/task.rb`, `lib/scout/workflow/task/*.rb` | Metadata container for task definitions; input resolution, dependency declaration |
| `Step` (class) | `lib/scout/step.rb`, `lib/scout/workflow/step.rb`, `lib/scout/workflow/step/*.rb` | Execution unit: runs, manages dependencies, persists results, tracks status |
| Deployment | `lib/scout/workflow/deployment/` | HPC scheduler integration (SLURM, PBS, LSF) and Singularity |

## Task lifecycle

### Definition phase

When a workflow module is loaded, `task :name => :type do ... end`
creates a Task object. The DSL methods (`input`, `dep`, `returns`,
`extension`) called before `task` accumulate metadata:

```ruby
input :data, :file, "Data file"
dep :preprocess
returns :tsv
extension :tsv
task :analyze => :tsv do
  # ...
end
```

The metadata is stored as annotations on the task (Task extends
`Annotation`). The `task` method:
1. Creates a Task object.
2. Attaches accumulated annotations (inputs, deps, returns, extension).

The `annotate_next_task` mechanism uses class-level instance variables to
queue annotations for the next task definition. This is how `input`, `dep`,
`returns`, and `extension` work — they don't create tasks; they annotate
the next one.

### Job creation (instantiation)

When you call `workflow.job(:task_name, "job_id", inputs)`:

1. The Task resolves its inputs (applying defaults, checking types).
2. The Task creates a Step with:
   - A path derived from the task name and a digest of the inputs.
   - The task block as the execution code.
   - Dependency declarations.
3. The Step is returned to the caller.

### Execution (Step.run)

When `.run` (or `.produce`, `.fork`) is called on a Step:

1. **Dependency resolution**: `run_dependencies` resolves each declared
   dependency. This recursively creates Steps for dependencies and runs
   them.
2. **Dependency preparation**: `prepare_dependencies` checks if
   dependencies are up-to-date. If a dependency's result is older than its
   own dependencies, it is cleaned and recomputed.
2. **Input collection**: The task's inputs are gathered from the Step's
   input values and from dependencies (via `step(:name)`).
3. **Execution**: The task block is executed in the context of the Step.
   `step(:name)` provides access to dependencies.
4. **Result persistence**: The result is serialized to the Step's path.
5. **Provenance**: Status, timestamps, PID, and exception details are
   written to the `.info` sidecar file.

### Path convention

```
var/jobs/<Workflow>/<task>/<digest>.<ext>
```

The digest is an MD5 of the job's input values and dependency signatures.
This ensures:
- Identical inputs produce identical paths (cache hit).
- Different inputs produce different paths (no collision).
- Dependency changes change the digest (because dependency signatures
  include their own digests).

### Dependency resolution

Dependencies are declared with `dep` and resolved at runtime. The
resolution process:

1. `dep :name` creates a dependency declaration on the task.
2. At job creation, the dependency is instantiated as a Step.
3. At execution time, `run_dependencies` iterates over dependencies and
   runs them (potentially in parallel using threads or forks).
4. Inside the task block, `step(:name)` accesses the resolved dependency.

Dependencies can be:
- **Static**: `dep :upstream_task`
- **Dynamic**: `dep do |inputname, inputs| ... end` (block decides at
  runtime)
- **From another workflow**: `dep OtherWorkflow, :task_name`
- **Overriding**: A dependency can override another dependency's result
  if they target the same logical step.

#### Compute options

Dependencies accept `compute:` options:
- `:canfail` — If the dependency fails, the parent task continues.
- `:produce` — Only produce the dependency result; don't load it.
- `:stream` — Stream the dependency result to the parent.

## Step lifecycle and status

A Step has a well-defined lifecycle with status transitions:

```
waiting → queued → start → done
                  ↘ error
                  ↘ aborted
                  ↘ cleaning → waiting
```

Status is persisted in the `.info` file. Key status values:
- `waiting` — Job not yet started.
- `done` — Job completed successfully.
- `error` — Job raised an exception.
- `aborted` — Job was killed.
- `cleaning` — Job is being cleaned for re-execution.

### Info file

The `.info` file records provenance:
- Status, status changes, timestamps (issued, start, done).
- PID and hostname.
- Inputs and their values.
- Dependencies and their paths.
- Exception details (including backtrace) if an error occurred.
- Log messages from the task.

The serializer is configurable via `SCOUT_SERIALIZER` (default: JSON).

## Deployment to HPC

The `Workflow::Scheduler` subsystem supports submitting jobs to HPC
clusters.

| Scheduler | File |
|-----------|------|
| SLURM | `lib/scout/workflow/deployment/scheduler/slurm.rb` |
| PBS | `lib/scout/workflow/deployment/scheduler/pbs.rb` |
| LSF | `lib/scout/workflow/deployment/lfs.rb` |

The scheduler:
1. Groups jobs into batches based on resource rules.
2. Generates submission scripts.
3. Submits via the cluster's command-line tool (`sbatch`, `qsub`, etc.).
4. Monitors job status.
5. Orchestrates dependencies across batch jobs.

Rules specify resources per task:

```ruby
rules = {
  "MyWorkflow" => {
    "heavy_task" => { cpus: 16, time: "24h", mem: "64G", queue: "long" },
    "light_task" => { cpus: 1, time: "1h", mem: "2G" }
  }
}
```

### Singularity containers

The scheduler can wrap jobs in Singularity containers for reproducibility.
This is configured in the rules with container options.

## Provenance and the info file

The info file is the core of the provenance system. It's a JSON (or
Marshal) file that records everything about a job execution:

| Field | Purpose |
|-------|---------|
| `:status` | Current status (waiting, done, error, etc.) |
| `:pid` | Process ID |
| `:issue_time` | When the job was first created |
| `:start_time` | When execution began |
| `:time_elapsed` | Total time from start to current |
| `:total_time_elapsed` | Total time including all dependencies |
| `:inputs` | Input values used |
| `:dependencies` | Paths of dependency results |
| `:exception` | Exception details if status is error |

The info file is updated continuously during execution, allowing
monitoring tools to track progress in real time.

## Extension points

### Adding a new scheduler

To support a new HPC scheduler:

1. Create `lib/scout/workflow/deployment/scheduler/<name>.rb`.
2. Implement the job submission script generation (see `slurm.rb` for a
   template).
3. Add the scheduler name to the `system` detection logic in
   `scheduler/job.rb`.

### Adding a new result type

To support a new return type for tasks:

1. Add the type to `Workflow::TYPE_EXTENSIONS` mapping.
2. Ensure the type is serializable via the TSV/JSON/Marshal serializers.

## Known issues

- The `cleaned_dependencies` method always returns `[]` (dead code).
- The `REMOVE_TASK_ALIAS` environment variable behavior is subtle and may
  not work as expected.
- Scheduler job state tracking can be fragile if the batch directory is
  corrupted.
- Info file serialization format changed from Marshal to JSON; old info
  files may not be readable by newer versions.

## See also

- [Architecture](Architecture.md)
- [Persistence Engines](PersistenceEngines.md)
- [Concurrency Model](ConcurrencyModel.md)
- [Research: Workflow Engine Analysis](../../research/workflow-engine-analysis.md)
