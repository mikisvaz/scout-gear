# HPC / Batch Execution

This document explains how scout-gear runs workflows on clusters: the
configuration keys that control dispatch, batch engines, job chains, and
the scheduler state directory.

It is intended for workflow authors who need to run large analyses on an
HPC cluster.

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
'env:BATCH_SYSTEM', default: 'SLURM'` (scheduler.rb:38); an unknown name
raises `Unknown batch system` (scheduler.rb:76).

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

Keys in the second half of that range (`:queue` … `:singularity_ruby_inline`,
job.rb:170-185) additionally pick up defaults from scout config keys such as
`batch_queue` / `queue` / `batch`.

`config_keys` entries are `key value [tokens...]`: `cpus 20 samtools`
sets the scout config `cpus` to `20` when running `samtools` tasks.
Tokens such as `workflow:HTS` scope an override to one workflow; the
shorthand `forget_dep_tasks true forget_dep_tasks` shows key/value plus
scope token.

## Scheduler state

Each submission writes a batch directory (default under
`var/<workflow>/batch/...`, overridable with `batch_dir`) containing the
generated submission script, the step manifest
(`manifest => batch[:jobs].collect{|d| d.task_signature}`),
scheduler.rb:58), and job status tracked via the engine's
`job_status(job)` (slurm.rb:147, querying the scheduler). Dependencies
between batches are passed as `batch_dependencies` job ids, optionally
prefixed `canfail:` for dependencies allowed to fail (scheduler.rb:51).

## CLI: `scout batch` commands

The `scout` CLI ships batch management subcommands
(`scout_commands/batch/`), which operate on batch directories (default
`~/scout-batch`):

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

## See also

- [Building Workflows](BuildingWorkflows.md) — defining tasks and running
  jobs locally (`job.run`, `job.produce`).
