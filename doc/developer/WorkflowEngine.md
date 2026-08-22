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
| `Workflow` (module) | `lib/scout/workflow.rb`, `lib/scout/workflow/definition.rb` | DSL context: `input`, `task`, `dep`, `helper`, `extension` |
| `Task` (module) | `lib/scout/workflow/task.rb`, `lib/scout/workflow/task/*.rb` | Metadata container for task definitions; input resolution, dependency declaration |
| `Step` (class) | `lib/scout/step.rb`, `lib/scout/workflow/step.rb`, `lib/scout/workflow/step/*.rb` | Execution unit: runs, manages dependencies, persists results, tracks status |
| Deployment | `lib/scout/workflow/deployment/` | HPC scheduler integration (SLURM, PBS, LSF), local, and queue dispatch |

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

The `annotate_next_task` mechanism (`workflow/definition.rb`) uses
class-level instance variables to queue annotations for the next task
definition. This is how `input`, `dep`, `returns`, and `extension` work —
they don't create tasks; they annotate the next one.

`returns` is not a standalone DSL method — the return type is the value
after `=>` in the `task` declaration (e.g. `task :analyze => :tsv`).
`extension` sets the result file extension; `TYPE_EXTENSIONS`
(`workflow/definition.rb:5`) maps `tsv`/`yaml`/`json`/`marshal` types to
their extensions automatically, so `task :t => :tsv` implies
`extension :tsv`. A Symbol type defaults to `:binary` unless mapped.

### Job creation (instantiation)

When you call `workflow.job(:task_name, "job_id", inputs)`:

1. `Task#job` (`workflow/task.rb:34`) resolves the inputs
   (`process_inputs`, `task/inputs.rb:90`): applies defaults, coerces
   string values to the declared type (`format_input`,
   `task/inputs.rb:3` — e.g. `:integer`/`:float` strings become numbers;
   a `String` for a loadable type is read from file unless the type is
   `path`/`file`/`folder`/`binary`/`tsv` or `noload`/`stream`/`asfile`
   are set), and computes an input digest.
2. Dependencies are instantiated (`dependencies(id, provided_inputs,
   non_default_inputs, compute)`).
3. A job path is built: `var/jobs/<Workflow>/<task>/<name>_<md5>.<ext>`
   where the MD5 is over `{:inputs => input_digest_str,
   :dependencies => dependencies}` (`workflow/task.rb:110`).
4. The workflow memoizes jobs: the same `workflow.job(...)` call returns
   the same Step object (`workflow.rb:171`, via `Persist.memory`), and
   extends it with the workflow's `step_module` so task blocks and
   helpers run in its context.
5. The Step is returned to the caller.

### Execution (Step.run)

When `.run` (or `.produce`, `.fork`) is called on a Step:

1. **Dependency resolution**: `run_dependencies` resolves each declared
   dependency, recursively creating and running Steps.
2. **Dependency preparation**: `prepare_dependencies` checks whether
   dependencies are up to date. A step is `updated?` when it is done and
   no dependency is newer (`newer_dependencies`,
   `step/status.rb:23-40`); otherwise it is cleaned and recomputed
   unless `SCOUT_UPDATE=true` or the error is non-recoverable
   (`step/status.rb:42-52`).
3. **Input collection**: The task's inputs are gathered from the Step's
   input values and from dependencies (via `step(:name)`).
4. **Execution**: The task block is executed in the context of the Step
   (the workflow's step module). `step(:name)` provides access to
   dependencies.
5. **Result persistence**: The result is saved to the Step's path
   (streamed results are written in a background thread;
   `workflow/step.rb:265`).
6. **Provenance**: Status, timestamps, PID, and exception details are
   written to the `.info` sidecar file.

### Path convention

```
var/jobs/<Workflow>/<task>/<name>_<md5>.<ext>
```

The digest is an MD5 of the input digest and the dependency signatures
(`workflow/task.rb:110`). This ensures:
- Identical inputs and dependencies produce identical paths (cache hit).
- Different inputs or dependencies produce different paths.
- Dependency changes change the digest, because dependency signatures
  include their own paths.

The base directory defaults to `var/jobs` and is configurable via
`Scout::Config.get(:directory, :workflow_jobs, :workflow, :jobs)`
(`workflow/definition.rb:19`).

### Dependency resolution

Dependencies are declared with `dep` and resolved at runtime. The
resolution process:

1. `dep :name` creates a dependency declaration on the task.
2. At job creation, the dependency is instantiated as a Step.
3. At execution time, `run_dependencies` iterates over dependencies and
   runs them.
4. Inside the task block, `step(:name)` accesses the resolved dependency.

Dependencies can be:
- **Static**: `dep :upstream_task`
- **Dynamic**: `dep do |inputname, inputs| ... end` (block decides at
  runtime)
- **From another workflow**: `dep OtherWorkflow, :task_name`
- **Aliased**: `task_alias(name, workflow, oname)` renames a task from
  another workflow for use in `dep` (`workflow/definition.rb:157`).
- **Overriding**: a dependency can override another dependency's result
  if they target the same logical step.

#### Compute options

Dependencies accept `compute:` options (`step/dependencies.rb:114-127`):
- `:canfail` — If the dependency fails, the parent task continues
  (`canfail?`, `step/status.rb:79`).
- `:produce` — Only produce the dependency result; don't load it.
- `:stream` — Stream the dependency result to the parent.

#### Dependency input files

A step's linked auxiliary files live in `<path>.files/`
(`step/file.rb:2`). `file('name')` resolves a path inside that
directory; task blocks typically write there and record the file in the
result.

## Step lifecycle and status

Step status is stored in the `.info` file and read back with `status`
(`step/info.rb:182`). The statuses actually written by the code are:

- `:waiting` — `init_info` default before execution
  (`step/info.rb:44`).
- `:setup` — set when `run` begins, with `:issued` timestamp
  (`step.rb:210`).
- `:start` — when execution of the block starts (`step.rb:220`).
- `:done`, `:error`, `:aborted` — terminal states
  (`step.rb:252-285`).

Transitions:

```
waiting → setup → start → done
                  ↘ error
                  ↘ aborted
```

There is no `queued` or `cleaning` status in this implementation.
Predicates (`step/status.rb`, `step/info.rb`):
- `waiting?` — present but not started.
- `started?` — done, or a live PID is recorded.
- `running?` — not done-with-`:done` and the recorded PID is alive.
- `streaming?` — result is an IO/stream not yet consumed (`step.rb:316`).
- `done?` — the result file exists (`step.rb:312`).
- `dirty?` — done but not `updated?`.
- `error?`, `aborted?` — status checks.
- `clean` / `recursive_clean` remove the result, `.info`, temp file, and
  `.files` directory (`step/status.rb:53-68`).

### Info file

The `.info` file records provenance:
- Status and status changes, `issued`, `start`, `end` timestamps.
- PID (and hostname in deployment contexts).
- Inputs and their values.
- Dependencies and their paths.
- Exception details and backtrace if an error occurred.
- Log messages from the task.

The serializer is configurable via `SCOUT_SERIALIZER` (default: JSON)
(`step/info.rb:6`).

## Deployment to HPC

The `Workflow::Scheduler` subsystem supports submitting jobs to HPC
clusters, plus local and queue dispatch.

| Scheduler | File |
|-----------|------|
| SLURM | `lib/scout/workflow/deployment/scheduler/slurm.rb` |
| PBS | `lib/scout/workflow/deployment/scheduler/pbs.rb` |
| LSF | `lib/scout/workflow/deployment/scheduler/lfs.rb` |
| local | `lib/scout/workflow/deployment/local.rb` |
| queue | `lib/scout/workflow/deployment/queue.rb` |

The scheduler (`deployment/scheduler.rb`):
1. Groups jobs into batches based on resource rules (orchestrator:
   `deployment/orchestrator/{workload,batches,chains,rules}.rb`).
2. Generates submission scripts (`#SBATCH`/`#PBS`/`#BSUB` headers —
   `scheduler/slurm.rb:27`).
3. Submits via the cluster's command-line tool (`sbatch`, `qsub`,
   `bsub`).
4. Monitors job status (`job_status`, `scheduler/slurm.rb:147`).
5. Orchestrates dependencies across batch jobs.

The batch system is selected with
`Scout::Config.get(:system, :batch, :scheduler, 'env:BATCH_SYSTEM',
default: 'SLURM')` (`deployment/scheduler.rb:38`); unknown systems raise.

Rules specify resources per task, typically loaded from YAML files under
`~/.scout/etc/batch/`. Example structure (as used by the real
configuration files there):

```yaml
defaults:
  containers: false
  log: 0
  profile: default

chains:
  ...
config_keys:
  ...
workflow:
  <WorkflowName>:
    <task_name>:
      time: 4h
      cpus: 8
      config_keys: key1 value1
```

See [HPC / Batch Execution](../user/HPCBatchExecution.md) for the
user-facing view.

### Singularity containers

The scheduler can wrap jobs in Singularity containers for
reproducibility (`container`/`containers` rule keys;
`scheduler/job.rb`).

## Extension points

### Adding a new scheduler

To support a new HPC scheduler:

1. Create `lib/scout/workflow/deployment/scheduler/<name>.rb`
   implementing `system`, `batch_system_variables`, `header`,
   `run_template`, and `job_status` (see `slurm.rb`).
2. Add the batch system name to the dispatch in
   `deployment/scheduler.rb:66-76` so `process_batches` selects it.

### Adding a new result type

To support a new return type for tasks:

1. Add the type to `Workflow::TYPE_EXTENSIONS` mapping
   (`workflow/definition.rb:5`) if it should imply a file extension.
2. Ensure the type is serializable via the TSV/JSON/Marshal serializers
   (TSV persistence adapters, `persist/tsv.rb`).

## Known issues

- The `cleaned_dependencies` method always returns `[]` (dead code at
  `step/status.rb:33`).
- Info file serialization format changed from Marshal to JSON; old info
  files may not be readable by newer versions.
- Scheduler job state tracking can be fragile if the batch directory is
  corrupted.

## See also

- [Architecture](Architecture.md)
- [Persistence Engines](PersistenceEngines.md)
- [Concurrency Model](ConcurrencyModel.md)
- [Building Workflows](../user/BuildingWorkflows.md)
