# HPC / Batch Execution

This document explains how scout-gear runs workflows on clusters: the
configuration keys that control dispatch, batch engines, job chains, and
the scheduler state directory.

It is intended for workflow authors who need to run large analyses on an
HPC cluster.

Workflows reach this subsystem in two ways: `Workflow.produce(jobs)`
(`scout ... local`/`workers`) runs everything on the current host through
`Workflow::LocalExecutor`, while `Workflow::Scheduler.produce(jobs)`
(`scout ... batch`/`sched`/`cluster`/`slurm`/`pbs`/`lsf`) submits cluster
jobs. Both go through the same rules files, so the configuration below
applies to local parallel execution too. `Workflow::Scheduler.produce_single_batch`
collapses the whole workload into one job and dispatches it locally.

A batch's `deploy` rule (`rules[:deploy]`, local.rb:231) selects the
dispatch target with literal string matching: `nil`, `'local'`, `:local`,
`'serial'`, `:serial` run locally (forked step under `Config.with_config`);
`'batch'`, `'sched'`, `'slurm'`, `'pbs'`, `'lsf'` submit through
`Workflow::Scheduler`; any other value is treated as a *server name* and
dispatched offsite via `OffsiteStep` (a trailing `-batch` only adds
`batch: true`). Matching is literal — `:SLURM` or `'slurm '` fall through
to the offsite branch.

## Batches

The unit of dispatch is a **batch**: one job list, one `top_level` step,
one merged rule set. `Workflow::Orchestrator.job_batches(rules, jobs)`
builds one batch per step by default, ordered so that dependencies come
strictly before dependents (`batches.rb:149 sort_batches`). `skip` and
`chains` merge steps into the batch of their dependent, and the merged
batch keeps the *dependent* as its `top_level`
(`batches.rb:88-110`). A chain listing a single task merges nothing.

Steps already finished are dropped at dispatch time, not at composition
time: `clean_batches` keeps done batches in the list and
`run_batch`/`process` skips them
(`workload.rb:52 done_batch?` — `done? || running? || (error? && !recoverable_error?)`).

One caveat of `done_batch?`'s `running?` clause: `Step#running?` checks
`Misc.pid_alive?(info[:pid])`, and `pid_alive?` short-circuits on
`Process.pid == pid` — so an errored step produced *in the current
process* counts as running and is skipped on resume within that process.

## Batch engines

Batch submission is implemented in
`lib/scout/workflow/deployment/scheduler/` with three engines:

- `SLURM` — emits `#SBATCH` headers and calls `sbatch`
  (slurm.rb);
- `LSF` — emits `#BSUB` headers and calls `bsub` (lfs.rb — note the
  filename spelling);
- `PBS` — emits `#PBS` headers (pbs.rb).

`Workflow::Scheduler.process_batches` (scheduler.rb:32) selects the
engine via `Scout::Config.get :system, :batch, :scheduler,
'env:BATCH_SYSTEM', default: 'SLURM'`.

Two footnotes on that lookup: the flat key form `scheduler PBS` (and
`system batch scheduler PBS`) does **not** resolve — write the tokens in
order, `system PBS batch scheduler`. And `BATCH_SYSTEM` as an environment
variable alone does not select the engine: the `'env:BATCH_SYSTEM'` token
in the key list is inert; what works is `env:NAME` as a *value*
(`system env:BATCH_SYSTEM batch scheduler`, resolved at
config-processing time). Each engine exports `BATCH_SYSTEM` into the job
script (`export BATCH_SYSTEM=…`) to record `batch_system` info; it is not
read on the submitting side. Lowercase `slurm`/`pbs`/`lsf` (and any other
unknown name) raise `Unknown batch system` (scheduler.rb:76).

## Configuration

Batch configuration is plain scout configuration (see
[Configuration](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/Configuration.md)),
typically provided as YAML files under `~/.scout/etc/batch`. `default.yaml`
supplies global defaults and per-workflow files (e.g. `HTS.yaml`) layer
on top. The following rule kinds are understood:

- `defaults` — options applied to every job (e.g. `account`, `time`);
- `skip` — rule key that merges a batch's jobs into the batch of its
  dependent instead of submitting it separately (`true`/`false` per task
  or workflow; rules.rb:58-65, batches.rb:88-110);
- `chains` — task chains submitted as one job (below).

Note that only `defaults`, per-workflow blocks, `skip` and `chains` are
processed; other blocks in these files (such as `keep:` in the example
below) are ignored.

When jobs from several workflows are being produced, the rules of every
workflow in each job's dependency tree are loaded in addition to the
default file (`load_rules_for_job`, rules.rb:241).

### Rule merging

Two different merges apply, and they do not behave alike:

- **Within one job's rule resolution** (`job_rules`,
  rules.rb:87) the chain `task_specific_rules` → workflow `defaults` →
  global `defaults` is folded with `merge_rules`
  (rules.rb:21): first-wins per key. An earlier (more specific) value is
  never overridden, with one exception — `config_keys` entries are
  concatenated by `add_config_keys` (rules.rb:4) instead of being
  dropped.
- **Across a dependency tree and across the jobs of a batch**
  (`accumulate_rules`, rules.rb:41) the merge is value-aware: `cpus` and
  `task_cpus` take the **max**, `time` takes the longest, `config_keys`
  concatenate, `skip` combines with *and* (a `false` anywhere unskips
  the accumulated set), and all other keys stay first-wins.

A step's effective batch rules are therefore its own task rules
accumulated over every dependency's rules — requesting `task_cpus: 20`
on a step raises the merged batch to 20 if a dependency needs that many.

### Local resources

`task_cpus` is not only a scheduler option. For local execution it is
read as a **resource key**: `normalize_resources_from_rules`
(rules.rb:179) accepts `task_cpus` as an alias for `cpus` (nested
`resources:` win over top-level `cpus`/`task_cpus`/`IO`/`io`/`mem`/
`mem_per_cpu`, with `default_resources`/`defaults.resources` filling
unset keys), and `LocalExecutor` (local.rb) tracks the numeric result
per batch in plain in-process counters
(`available_resources`/`resources_requested`/`resources_used`), starting
from `cpus: Etc.nprocessors`. Non-numeric values (and `size`) are
dropped before the check, so `time`, `queue` and similar keys never gate
local dispatch; a batch whose only resource is `cpus` waits until the
running total plus its request fits `available_resources[:cpus]`.

The class-level helper `LocalExecutor.produce(jobs, rules, produce_cpus:
Etc.nprocessors, produce_timer: 1, bar: nil)` builds the executor; the
executor's own `initialize(timer = 5, …)` is the poll interval (seconds)
for re-checking the resource counters. `Workflow.produce` (deployment.rb)
only loads rules and forwards `...`. The gate is a plain in-process
counter, not a POSIX semaphore: nothing is written to disk for it.

## Job chains

A chain declares a set of tasks run together as **one** cluster job
(orchestrator/chains.rb:17 `parse_chains`, chains.rb:78 `job_chains`):

```yaml
chains:
  pre_align:
    workflow: HTS
    tasks: uBAM, mark_adapters
    task_cpus: 1
    time: 40h
```

`tasks` is a comma-separated list of step types. A `Workflow#Task` entry
refers to a task in a different workflow — the part before `#` names the
workflow, the part after the task; if `workflow:` is given it is used for
entries without an explicit `#`. Chain `rules` (everything but `tasks`
and `workflow`) become the batch options for the single job.

The merged batch keeps the **last task of the chain** (the dependent) as
its `top_level`, and the chain's rule keys become the batch rules —
exactly like a `skip`-merged batch (see [Batches](#batches)).

## Batch options

`Workflow::Scheduler::Job.batch_options` (job.rb:119) recognizes the
options below. Defaults: `task_cpus: 1`, `time: '2min'`, `nodes: 1`
(job.rb:225-231).

| Option | Meaning |
|--------|---------|
| `task_cpus` | CPUs requested (SBATCH `--cpus-per-task`) |
| `time` | Walltime (e.g. `4h`, `40h`, `10m`) |
| `queue` / `partition` | Queue/partition name |
| `account` | Billing account |
| `mem`, `mem_per_cpu`, `gres`, `licenses` | Resource requests |
| `nodes` | Node count (default 1) |
| `exclusive`, `highmem`, `constraints` | Scheduler flags |
| `lua_modules` | Modules loaded via LMod before the job |
| `conda` | Conda environment to activate |
| `contain` / `sync` / `contain_and_sync` / `copy_image` | Container/sync deployment |
| `launcher` | Parallel launcher used inside the job |
| `batch_dir`, `batch_name` | Override scheduler bookkeeping paths |
| `config_keys` | Scout config overrides applied while running (parsed by `config_keys`/`Scout::Config`) |
| `development`, `env_cmd`, `env`, `workdir`, `user_group`, `purge_deps` | Environment/wrapper options (job.rb:124-158) |
| `singularity*` (`singularity`, `singularity_img`, `singularity_mounts`, `singularity_opt_dir`, `singularity_ruby_inline`), `wipe_container` | Container options (job.rb:124-158) |

The option table is engine-agnostic as far as the options are *read*;
how each engine emits them differs. SLURM maps one `#SBATCH` line per
option (`task_cpus→--cpus-per-task`, `time→--time` normalized to
`HH:MM:SS`, `queue→--qos`, `account→--account`, `partition→--partition`,
`mem→--mem`, `gres` one line per entry, `constraints`, `exclusive`,
`licenses`, `nodes`, plus `--job-name`/`--output`/`--error`). **PBS only
emits `walltime`, `queue`, `account`, output/error and `-k doe`; the
`task_cpus`, `nodes`, `time`, `constraint`, `exclusive`, `licenses`,
`gres`, `mem` and `mem_per_cpu` entries are extracted and then commented
out in pbs.rb, so requesting them under PBS is silently ignored.** LSF
emits `-J/-cwd/-oo/-eo/-q/-n/-W/-x`, carrying `task_cpus` in `-n` and
walltime as `HH:MM` in `-W`.

Keys in the second half of that range (`:queue` … `:singularity_ruby_inline`,
job.rb:170-185) additionally pick up defaults from scout config keys such as
`batch_queue` / `queue` / `batch`.

`config_keys` entries are `key value [tokens...]`: `cpus 20 samtools`
sets the scout config `cpus` to `20` when running `samtools` tasks.
Tokens such as `workflow:HTS` scope an override to one workflow; the
shorthand `forget_dep_tasks true forget_dep_tasks` shows key/value plus
scope token. A value of the form `env:NAME` is resolved at
config-processing time — `cpus env:SLURM_CPUS_PER_TASK samtools_index`
therefore picks up the variable set by the batch system, or stays unset
(and is skipped) when the variable is not set.

## Scheduler state

Each submission writes a batch directory containing the generated
submission script, the step manifest, and job status. The manifest is
the comma-joined `task_signature` of every job in the batch
(`#MANIFEST: …`, scheduler.rb:63; a signature is `Workflow#task`, no
job name), which is how `skip`-merged and chained batches still record
all the steps they cover. Status is tracked via the engine's
`job_status(job)` (slurm.rb:147, querying the scheduler).

Dependencies between batches are passed as `batch_dependencies` job ids
grouped `canfail:`-prefixed versus plain (scheduler.rb:51): plain
dependencies become one `afterok:` group and `canfail:` ones one
`afterany:` group (SLURM `--dependency=afterok:A:B,afterany:C`; LSF
`-w`, PBS `-W depend=`). The prefix is not something you type in the
configuration — it is derived from the dependency step's `canfail?`
predicate, which only the `dep` DSL sets (`dep :risky, compute:
:canfail` in the workflow definition; see
[Building Workflows](BuildingWorkflows.md)).

Batch directories default to `~/scout-batch/` (`batch_base_dir`, or
`batch_dir`), named after the system, workflow and task — for example
`~/scout-batch/SLURM_scout_job-W-task-<random>/`. The files in there are
what the `scout batch` commands below read.

`dry_run: true` (a `run_job` option) generates the submission script,
prints the `sbatch`/`bsub`/`qsub` command and submits nothing: the
engine raises `DryRun` and `process_batches` returns the batch directory
as its result (scheduler.rb:79).

## CLI: `scout batch` commands

The `scout` CLI ships batch management subcommands
(`scout_commands/batch/`), which operate on batch directories (default
`~/scout-batch`) — see [Using the CLI](UsingTheCLI.md) for the shared
option convention and exit codes:

- `scout batch list` — list jobs; filters `-d/-e/-a/-r/-q`
  (done/error/aborted/running/queued), `-j` job ids, `-s` regex search,
  `-t` tail of STDERR, `-p` progress of job and dependencies,
  `-BP` batch parameters, `-BPP` Procpath performance summary,
  `-sacct` sacct performance summary, `-bs` batch system override
  (`auto`, `lsf`, `slurm`).
- `scout batch tail <directory|jobid|step>` — follow a job's output;
  `-bs` selects the batch system (`auto` by default).
- `scout batch clean` — remove batch directories; filters as for `list`,
  plus `-dr/--dry_run` to only report.

`scout batch tail` resolves its argument in three ways: a directory
containing `command.batch`, a scheduler job id (looked up in
`**/job.id`), or a step path (grep'd out of the `#STEP_PATH:` line in
the stored scripts).

## Example

An excerpt from a real `~/.scout/etc/batch/HTS.yaml`:

```yaml
keep:
 HTS: GC_windows, mutect2_pre, mutect2_filters, BAM_sorted, mutation_pileup, seqz, sequenza, BAM

skip:
 HTS: BAM, BAM_normal, BAM_rescore_realign
 Sample: caller_cohort, combined_caller_vcfs, consensus_somatic_variants, BAM, BAM_normal, mutect2, strelka, muse, varscan

chains:
 pre_align:
  workflow: HTS
  tasks: uBAM, mark_adapters
  task_cpus: 1
  time: 40h

HTS:
 defaults:
  config_keys: spark false GATK, forget_dep_tasks true workflow:Sample, remove_dep_tasks recursive workflow:Sample, cpus env:SLURM_CPUS_PER_TASK samtools_index, cpus 20 samtools
  lua_modules: samtools, htslib
  time: 4h
  queue: gp_bscls
 BAM_rescore:
  task_cpus: 20
  time: 40h
```

(The `keep:` block above appears in the real configuration but is **not**
processed by the rules engine — only `defaults`, per-workflow blocks, `skip`
and `chains` are; see rules.rb and chains.rb.)

Note how `BAM_rescore: task_cpus: 20` interacts with rule merging: the
`20` applies to that task's own batch, and any batch that accumulates
`BAM_rescore` as a dependency takes the `max` of the two `task_cpus`
values, not the last one.

## See also

- [Building Workflows](BuildingWorkflows.md) — defining tasks and running
  jobs locally (`job.run`, `job.produce`), including the `compute:
  :canfail` dependency option.
- [Using the CLI](UsingTheCLI.md) — the `scout` executable's dispatcher
  and shared option convention.
