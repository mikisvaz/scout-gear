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
they don't create tasks; they annotate the next one. Annotations are
consumed by the task defined immediately after them: an `input` declared
between two tasks belongs to the second one only, and a later task gets
no inputs from it.

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
4. The Step is memoized by `Task#job` through `Persist.memory`
   (`workflow/task.rb:47`): the same task/id/input signature returns the
   same Step object (`.equal? == true`). `workflow.job`
   (`workflow.rb:172`) then extends it with the workflow's `step_module`
   so task blocks and helpers run in its context.
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
   dependencies. The block's parameters receive **only the task's own
   declared inputs**, in declaration order with defaults applied — a
   block with fewer parameters silently drops extras, a one-parameter
   block gets the first input, a zero-parameter block gets `nil`, and
   keyword arguments are not supported. Dependency results never arrive
   as positional arguments; `input[...]` is not an accessor in this
   context.
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
(`workflow/task.rb:110`). Only **non-default** inputs participate: giving an
input its own default value yields the same path as omitting it, so an
all-defaults job is `<id>` (literally `Default`) and a job with any
non-default input is `<id>_<md5>`. The digest is order-independent: it is
built from the input array, so two non-default inputs swapped produce the
same digest. This ensures:
- Identical inputs and dependencies produce identical paths (cache hit).
- Different inputs or dependencies produce different paths.
- Dependency changes change the digest, because dependency signatures
  include their own paths.

The Step is memoized by `Task#job` through `Persist.memory`
(`workflow/task.rb:47`, keyed on workflow/task/id and the
non-default inputs of the task's `recursive_inputs`): repeated identical
calls return the **same Step object** (`.equal? == true`), and different
input sets return different objects. `workflow.job`
(`workflow.rb:172`) then extends the Step with the workflow's
`step_module` before returning it.

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
- **From another workflow**: `dep OtherWorkflow, :task_name`. The
  dependency Step resolves to the **producer workflow's** task directory
  and records that path in the consumer's `info[:dependencies]`; it is
  reused in place, not copied or rebranded. The producer's job-path digest
  participates in the consumer's digest: a different input to the
  producer's task produces a different producer path and therefore a
  different consumer path.
- **Aliased**: `task_alias(name, workflow, oname)` renames a task from
  another workflow for use in `dep` (`workflow/definition.rb:157`). The
  alias is a distinct task with its own job directory under the alias
  name (`alias? == true` on both Task and dep Step); it declares the
  original as its dependency and joins it before finishing, so
  `alias.load` equals the producer's result while the alias's own path
  differs from the producer's.
- **Included**: `include_workflow(workflow)` merges the other workflow's
  tasks and helpers into the including workflow, but each borrowed task
  keeps its producer's directory, `task_signature`, `info[:workflow]` and
  Step `workflow` object — included tasks are not relocated or rebranded
  (`workflow/definition.rb:232`).
- **Overriding**: a dependency can override another dependency's result
  if they target the same logical step.

#### Compute options

Dependencies accept `compute:` options. They are collected by
`Task#dependencies` into a map keyed by the dependency's absolute path and
holding stringified option lists (`["canfail"]`, `["produce"]`), and
consumed by `run_dependencies`
(`step/dependencies.rb:109`):
- `:canfail` — If the dependency fails, the parent task continues
  (`canfail?`, `step/status.rb:79`). The dependency stays in the list with
  `status == :error`; `dep.load` raises the stored exception, and the
  parent block still receives `nil` for it — the failure is only visible
  through `step(:name).status` / `.error?`.
- `:produce` — Only produce the dependency result; don't load it.
- `:stream` — Stream the dependency result to the parent.
- `false` — Skip the run/wait loop for that dependency
  (`next if compute_options.include?(false)`,
  `step/dependencies.rb:117`). This is "do not force or wait", not "do not
  run at all": the dependency stays in the dependency list, is consumed
  normally if its result is already on disk, and is simply left absent if
  it is not (the parent still completes).

#### Dependency input files

A step's linked auxiliary files live in `<path>.files/`
(`step/file.rb:2`). `file('name')` resolves a path inside that
directory; task blocks typically write there and record the file in the
result.

## Step lifecycle and status

Step status is stored in the `.info` file and read back with `status`
(`step/info.rb:189`). The statuses actually written by the code are:

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

The forked child writes one additional status, `:queue`
(`reset_info status: :queue, pid: Process.pid unless present?`,
`step.rb:296`); there is no `cleaning` status.

A step with **no `.info` file at all** reports `status == ""` (empty
string), not `waiting`: most predicates are then false (`waiting?`,
`started?`, `done?`, `dirty?`, `error?`, `aborted?`) while `updated?` is
true and `running?` is `nil`. `clean` returns a step to exactly this
state.

Predicates (`step/status.rb`, `step/info.rb`):
- `waiting?` — present but not started.
- `started?` — done, or a live PID is recorded.
- `running?` — not done-with-`:done` and the recorded PID is alive
  (`info.rb:201`). An errored step whose PID is still alive reports both
  `error? == true` and `running? == true`.
- `streaming?` — result is an IO/stream not yet consumed (`step.rb:316`).
- `done?` — the result file exists (`step.rb:312`), regardless of status.
- `dirty?` — done but not `updated?`.
- `error?`, `aborted?` — status checks.
- `clean` / `recursive_clean` remove the result, `.info`, temp file, and
  `.files` directory (`step/status.rb:53-68`).

### Error classes and recoverability

`ScoutException` (scout-essentials, `lib/scout/exceptions.rb:2`) marks
**controlled and reproducible** failures: the same call with the same
inputs raises the same exception every time, so the error is
**non-recoverable** — retrying cannot help. Unexpected exceptions (no
read permission, no network, a missing environment key) are environmental
and usually correctable outside the code, so the engine treats them as
**recoverable**.

| Class | Parent | Defined at |
|-------|--------|------------|
| `ScoutException` | `StandardError` | scout-essentials `lib/scout/exceptions.rb:2` |
| `ParameterException` | `ScoutException` | scout-essentials `lib/scout/exceptions.rb:16` |
| `MissingParameterException` | `ParameterException` | scout-essentials `lib/scout/exceptions.rb:17` |
| `ResourceNotFound` | `ScoutException` | scout-essentials `lib/scout/exceptions.rb:77` |
| `WorkerException` | `ScoutException` | `work_queue/exceptions.rb:12` |

rbbt-util aliases `RbbtException = ScoutException`
(`rbbt/util/misc/exceptions.rb:4`), so legacy `rescue RbbtException`
sites (e.g. `deployment/orchestrator/workload.rb:14`) behave as
`rescue ScoutException`.

One predicate decides the classification:

```ruby
def recoverable_error?                      # step/status.rb:19-21
  error? && ! (ENV['SCOUT_NO_RECOVERABLE_ERROR'].to_s.downcase == 'true') &&
            ! (ScoutException === self.exception)
end
```

An errored step is non-recoverable iff its stored exception is a
`ScoutException` descendant; every other error is recoverable.
`SCOUT_NO_RECOVERABLE_ERROR=true` makes all errors non-recoverable —
nothing is auto-cleaned or retried; useful to freeze failed jobs for
inspection. The variable is consumed nowhere else.

Engine behavior driven by `recoverable_error?`:

| Consumer | Behavior |
|----------|----------|
| `Step#produce` (`step.rb:398`) | `clean if error? && recoverable_error?` — only recoverable errors are cleaned so the step re-runs; a `ScoutException` step stays errored. |
| `prepare_dependencies` (`step/dependencies.rb:74-79`) | Non-recoverable errored dep raises `dep.exception` unless `canfail?`; the raise is recorded as the parent's own error (`step.rb:196-200`) and, being a `ScoutException`, makes the parent non-recoverable too. |
| `run_dependencies` (`step/dependencies.rb:109`) | `next if dep.error? && ! dep.recoverable_error?` (`:112`) — non-recoverable deps are skipped, not re-run; `dep.run` rescues `ScoutException` and honors only `compute: :canfail` (`step/dependencies.rb:125-130`). |
| `Step#join` (`step.rb:390`) | Re-raises the stored exception regardless of class. |
| Orchestrator (`deployment/orchestrator/`) | `workload.rb:12` cleans recoverable errored deps before execution; a batch whose top level errored non-recoverably counts as done (`workload.rb:53`); jobs with non-recoverable errors are reported as batch errors (`batches.rb:161`). |
| Local deployment (`deployment/local.rb:80-97`) | Recoverable error → `job.clean` plus one retry (`raise TryAgain`), then `failed_jobs`; non-recoverable → `failed_jobs` immediately. `local.rb:186` re-raises non-recoverable top-level errors after `NoWork`. |
| Entity properties (`workflow/entity.rb:83-90`) | Recoverable → `job.clean` and re-run; non-recoverable → `raise job.exception`. |

The exception class survives persistence:

- Error paths store `Step.encode_exception(e)` — `e.to_json`, which
  embeds `json_class` (`step/info.rb:205-207`; written at
  `step.rb:198,251-256`) — and `Step#exception`
  (`step/info.rb:209-215`) revives it with
  `JSON.parse(..., create_additions: true)`, so `recoverable_error?`
  sees the original class in a fresh process. The marshal-replacement
  branch below is therefore almost never taken on current Scout, since
  the default serializer is JSON (`step/info.rb:6`), not Marshal.
- If revival fails (class no longer resolvable), `Step#exception`
  returns a plain `Exception` built from the recorded messages
  (`step/info.rb:218-224`); such an error then reads as recoverable even
  though the original was a `ScoutException`.
- When a raw `Exception` object is merged into the info (streaming abort
  callback, `step.rb:269-275`) and cannot be `Marshal.dump`-ed,
  `merge_info` replaces it with a fresh `ScoutException` (or plain
  `Exception`) carrying the same message and backtrace
  (`step/info.rb:117-129`) — the marker is preserved on purpose.

Caveat — `scout clean` does not reproduce this classification
(`scout_commands/system/clean:118-124`). It reads `exception =
info[:exception][:class]`, but the stored exception is the encoded
`String` (see above), so `[:class]` raises into the `rescue` and the
status stays `error`; the removal regexp
(`scout_commands/system/clean:138`) then matches, so the job is removed
even when the engine classifies it as non-recoverable. Even with a class
in hand, `exception.superclass === ScoutException` (line 122) is false
for `ScoutException` itself and every descendant — `Module#===` on class
objects tests instance-of, not subclass-of — while
`ScoutException >= exception_class` would be the working form. A status
of `non_recoverable`, had it ever been set, would not match the removal
regexp; not matching is what keeps such jobs on disk.

### Info file

The `.info` file records provenance:
- Status and status changes, `issued`, `start`, `end` timestamps.
- PID (and hostname in deployment contexts).
- Inputs and their values (`inputs`, `input_names`, `provided_inputs`,
  `non_default_inputs` are all persisted verbatim).
- Dependencies and their paths — the **direct** dependencies only. Each
  `.info` records one level, so a deep chain must be reconstructed by
  walking the recorded paths; the in-memory `rec_dependencies`
  (`step/dependencies.rb:3`) resolves the full chain, and a Step reloaded
  from disk rebuilds only the direct level from its info.
- Exception details and backtrace if an error occurred.
- Log messages from the task.

The serializer is configurable via `SCOUT_SERIALIZER` (default: JSON)
(`step/info.rb:6`).

## Remote steps (scout-camp `OffsiteStep`)

Offsite execution is provided by the `scout-camp` gem, not by scout-gear
itself. `scout/workflow/deployment/local.rb:254-256` annotates a local job
with `OffsiteStep.setup(job, server: server, batch: true)` (or
`server: deploy`): `OffsiteStep` is a **module annotation applied to the
very same `Step` object**, not a separate class, so an offsite step still
`is_a?(Step)`. Its API surface on the annotated Step is
`run`, `done?`, `exec`, `info`, `orchestrate_batch`, `offsite_path`,
`inputs_directory`, plus the annotations `server`, `workflow_name`,
`clean_id`, `batch` (scout-camp `offsite/step.rb:8`).

The one scout-gear branch that special-cases remote steps —
`if defined?(RemoteStep) && RemoteStep === dep` in
`Workflow#include_workflow` (`workflow/definition.rb:212`) — is **dead
code in this repository**: no `RemoteStep` class exists in scout-gear or
in scout-camp (0.2.0), and scout-gear's own `Step` is never a
`RemoteStep`. Only the `OffsiteStep` annotation is real.

Local/remote interoperability is based on path *identification*, not path
identity: `Resource.identify(abs)` (scout-essentials
`resource/util.rb:2`) maps an absolute path to its workflow-relative form
(`var/...`), and `find(:user)` (or another map) maps it back to the
concrete file. `Step.load` uses this round-trip
(`Step.relocate`, `workflow/step/load.rb:1`) to read a result produced
under one `var` root from another — the denominator between a remote
host's job tree and the local one. Behaviours that need a reachable
remote host (result sync-back, `orchestrate_batch`, `hold_dependencies`)
are documented in scout-camp and are **not** asserted here; verifying
them requires a live host.

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
