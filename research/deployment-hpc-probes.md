# Investigation: Deployment / HPC — Probe Findings

> **Non-normative.** This document is a working investigation with
> implementation details, code exploration notes, and hypotheses. Refer
> to the authoritative doc (`doc/user/HPCBatchExecution.md`) for the
> user-facing contract.

Consolidated record of the seven probes run against the deployment
subsystem (`lib/scout/workflow/deployment/` — `local.rb`,
`scheduler.rb`, `scheduler/{job,slurm,pbs,lfs}.rb`,
`orchestrator/{rules,batches,chains,workload}.rb`, `queue.rb`,
`trace.rb`) during the documentation-consolidation campaign. Each probe
was executed through `Observation/probe(<name>)` and its receipt cached.
Claim identifiers below refer to the Cortex artifact
`scout-gear/deployment-hpc.md` (map `current`, 32 claims / 7 receipts),
which holds the full evidence chains.

All probes ran single-process or under a boxed `timeout`; batch
submission was always exercised as `dry_run`, and the one forking probe
forked only via `Step#fork`. Every statement promoted into
`doc/user/HPCBatchExecution.md` was re-verified against HEAD
`8a3a514d7200971179573a1e3808c1ba3bb9226c` (unchanged from the campaign
verification commit).

## Probe ledger

### `deploy_local_dispatch`

- **Probed**: `LocalExecutor` dispatch and resource accounting
  (`local.rb`) — the `deploy` rule's branch table, the resource gate's
  mechanism, and defaults, evaluated by driving the same `case`
  expression and counters the code uses, without forking.
- **Finding**: `rules[:deploy]` splits into exactly three branches —
  `nil`/`local`/`serial` fork the job locally (applying `config_keys`
  and `log` first), `batch`/`sched`/`slurm`/`pbs`/`lsf` hand the batch
  to `Workflow::Scheduler.process_batches`, and anything else is an
  *offsite* server name (`server-batch` for `OffsiteStep` with
  `batch: true`). The resource gate is a counter over limited keys
  only: nothing POSIX is involved, just the in-process hashes
  `resources_requested` / `resources_used` / `available_resources`
  (initialised `cpus: Etc.nprocessors`), so the README's "bounded by
  semaphores" wording is a misnomer. Defaults are
  `produce_cpus: Etc.nprocessors`, `timer: 5`.
- **Receipt**: `Observation/probe/deploy_local_dispatch_f4ba9d339ef454ca88dc1a4f7d7f7fa6.json`
- **Claims**: 3.1, 3.2, 3.3

### `deploy_local_end_to_end`

- **Probed**: what `LocalExecutor.process` actually does on disk for a
  tiny workflow end to end — the one probe allowed to fork (via
  `Step#fork`), run under `timeout`.
- **Finding**: local execution writes only `J` and `J.info` (plus
  `.files/` etc.) — no batch directories, no scheduler state. A
  `cpus: 2` resource rule really serializes the two heavy steps (a
  `task_cpus`/`cpus` limit is honoured by the counter), while steps with
  no limits are free to interleave. Errors surface as the normal step
  `error` status.
- **Receipt**: `Observation/probe/deploy_local_end_to_end_a5040fbac4020461dd7802d8fe70f0c0.json`
- **Claims**: 3.4, 3.5

### `deploy_orchestrator_batches`

- **Probed**: `Workflow::Orchestrator` batch construction
  (`batches.rb` + `chains.rb` + `workload.rb`) against a 5-step DAG
  under different rule sets.
- **Finding**: default batches are one per step, topologically sorted
  (`sort_batches`, deps strictly before dependents); `skip` merges the
  skipped job's batch into its *dependent's* batch (merged `top_level`
  is the dependent, `jobs` accumulate, rules merge via
  `accumulate_rules`), and `skip: false` restores the split. A chain
  produces the same absorption, with the chain's non-`tasks` keys as the
  batch rules; a one-task chain is a no-op. Done batches are *not*
  dropped at composition time — `clean_batches` keeps them and the skip
  happens at dispatch (`done_batch?`).
- **Receipt**: `Observation/probe/deploy_orchestrator_batches_f4c44982f6d7c03dd352a084c846f448.json`
- **Claims**: 5.1, 5.2, 5.3, 4.2, 4.3

### `deploy_scheduler_script_generation`

- **Probed**: the scheduler submission layer
  (`scheduler/{job,slurm,pbs,lfs}.rb`) at script-generation time —
  per-engine headers, `dry_run` behaviour, the `sbatch` command shape,
  and `env:BATCH_SYSTEM` resolution.
- **Finding**: each engine emits its own header dialect; **PBS extracts
  and then comments out** `task_cpus`, `nodes`, `time`, `constraint`,
  `exclusive`, `licenses`, `gres`, `mem`, `mem_per_cpu`, so those
  requests are silently ignored under PBS. The submission tail is
  `sbatch '<command.batch>'` with dependencies grouped
  `--dependency=afterok:A:B,afterany:C`. `dry_run: true` raises
  `DryRun` from inside the engine and `process_batches` returns the
  batch directory. The `launcher: :srun` default in `exec_cmd` is dead
  code (the guard compares `self.system == :slurm` while
  `SLURM.system` returns the string `"SLURM"`), so the default
  `#EXEC_CMD` is plain `scout`.
- **Receipt**: `Observation/probe/deploy_scheduler_script_generation_752ae371b1324cf42ac7f70e738ea0a8.json`
- **Claims**: 6.1, 6.3, 6.4

### `deploy_env_token_and_batch_dir`

- **Probed**: two configuration details the doc covers only partially —
  the `env:` token and the batch directory layout — plus `config_keys`
  parsing and the per-engine dependency strings.
- **Finding**: `env:NAME` is resolved on **values** (`Scout::Config`
  returns `ENV['NAME']` when set, `nil` otherwise; multiple candidates
  resolve to the first set one). The `env:` prefix on an *option-key
  list member* — as in scheduler.rb's `'env:BATCH_SYSTEM'` token — is
  inert, so `BATCH_SYSTEM` in the environment alone does not select the
  engine; the effective selector is the `system … batch scheduler`
  token chain. `config_keys` values resolve their `env:` forms at
  `process_config` time. Batch dirs default to
  `~/scout-batch/<SYSTEM>_scout_job-<wf>-<task>-<rand>/` via
  `batch_base_dir`/`batch_dir`, **not** `var/<workflow>/batch`.
- **Receipt**: `Observation/probe/deploy_env_token_and_batch_dir_a67caef358a1c129d7138e347048f4c4.json`
- **Claims**: 6.1, 6.2, 8.3

### `deploy_skip_canfail_manifest`

- **Probed**: three loose ends — where the `canfail:` dependency prefix
  comes from, what `#MANIFEST:` records, and how resume decides a batch
  is already done.
- **Finding**: `canfail:` is decided by the *step*, not by any batch
  string: `scheduler.rb:55` prefixes the dependency id iff
  `dep_target.canfail?`, which only the `dep ..., compute: :canfail`
  DSL sets (a job kwarg does not). The manifest is the joined
  `task_signature` (`Workflow#task`) of the batch's jobs.
  `done_batch?` is `done? || running? || (error? && !recoverable_error?)`,
  where `running?` requires a live pid and
  `Misc.pid_alive?` short-circuits on `Process.pid == pid` — an errored
  step whose recorded pid is this process is skipped through the
  `running?` clause.
- **Receipt**: `Observation/probe/deploy_skip_canfail_manifest_9b4bddf1c77993983c8b359c279db531.json`
- **Claims**: 7.1, 7.2, 5.3

### `deploy_queue_trace_cli`

- **Probed**: the two smallest deployment files no doc mentions —
  `queue.rb` (`Workflow.queue_job` and friends) and `trace.rb`
  (`trace_job_times`/`trace`).
- **Finding**: `queue_job` maps a `var/queue/W/F/name` path back to a
  Step by `require_workflow` (through the Path `workflows` map,
  `:current` first), and takes the job *name* as everything before the
  first `_` (`name2clean_name`), which is why queue entries are written
  `Workflow_Task_jobname`-style; `inputs_dir/inputs.json` must exist or
  `File.size` raises. `trace_job_times` returns a TSV built from step
  info `start`/`done`, skipping steps with no `:end`, with
  `Start.second`/`End.second` relative to the earliest start;
  `fix_gap: true` is dead code here — it calls `Misc.collapse_ranges`,
  which scout-essentials 1.9.0 does not define.
- **Receipt**: `Observation/probe/deploy_queue_trace_cli_a4d8ebee4bfb75b92eb236b29d8c214c.json`
- **Claims**: 8.1, 8.2, 8.3

## Consolidated observations

1. **Two rule merges with different semantics is the load-bearing fact.**
   `merge_rules` (within one job's rule resolution: task → workflow
   `defaults` → global `defaults`) is first-wins per key; `accumulate_rules`
   (down the dependency tree, and across the jobs merged into one batch)
   is value-aware — `max` for `cpus`/`task_cpus`, longest `time`,
   concatenated `config_keys`, and `skip` combined with *and*. The doc
   previously implied one merge. *(4.1, 4.2, 5.2)*

2. **The engine-selection story in the doc was wrong in one token.**
   The `'env:BATCH_SYSTEM'` token inside the `Scout::Config.get` key
   list is inert; what selects the engine is the token chain
   `system … batch scheduler`. `env:` resolution works on *values*
   (`system env:BATCH_SYSTEM batch scheduler` does work, and
   `config_keys: cpus env:SLURM_CPUS_PER_TASK …` resolves at
   `process_config` time). `BATCH_SYSTEM` is *exported by* the engines
   into the job script, not read on the submitting side. *(6.1, 8.3)*

3. **Options are read engine-neutrally but emitted engine-specifically.**
   `batch_options` accepts the whole option table for every engine, and
   then each header generator maps a different subset — under PBS most
   resource options are extracted and commented out, so a configuration
   that looks portable silently drops `mem`/`gres`/`task_cpus`/… on PBS.
   That drop-out is now stated explicitly in the option-table section
   rather than left to be discovered on the cluster. *(6.3)*

4. **Batch composition and resume are two separate steps.** Batches are
   composed for the whole workload (done steps included), sorted, and
   only then skipped at dispatch through `done_batch?` — whose
   `running?` clause trusts a recorded pid (`Misc.pid_alive?`
   short-circuits on the current process pid). This is why a resume can
   skip a step whose info is stale. *(5.1, 5.3)*

5. **`task_cpus` is two keys in one.** It is a scheduler option
   (`--cpus-per-task`) *and* a local resource key
   (`normalize_resources_from_rules` aliases it to `cpus`), so the same
   rules file drives local parallel dispatch and cluster submission.
   The local gate is a plain in-process counter over numeric keys,
   nothing POSIX. *(3.2, 4.1)*

## Deliberately not promoted (live-code defects)

These are behaviors of the code that the doc now describes as
warnings/caveats at most, not as normal behavior, because documenting
them as normal would freeze a defect. Improvements.md candidates
(owned by a separate agent):

- `SchedulerJob.exec_cmd`'s `launcher: :srun` default never fires: the
  guard tests `self.system == :slurm` while engines return strings
  (`"SLURM"`). *(6.4)*
- PBS header generation comments out `task_cpus`/`nodes`/`time`/
  `constraint`/`exclusive`/`licenses`/`gres`/`mem`/`mem_per_cpu`
  instead of emitting them. *(6.3)*
- `Workflow.trace_job_times(fix_gap: true)` calls
  `Misc.collapse_ranges`, undefined in scout-essentials 1.9.0 — any
  caller crashes with `NoMethodError`. *(8.2)*
- `scout workflow process` dies with
  `LoadError … deployment/orchestrator`: the repo ships
  `deployment/orchestrator/` (a directory) with no `orchestrator.rb`.
- `scout workflow trace` dies with `NoMethodError … Rbbt` from
  rbbt-util's `R/model.rb` (`require 'rbbt/util/R'`).
- The two entry points above are the reason the doc page's CLI section
  stays limited to `scout batch …`: the workflow-level `process`/`trace`
  commands cannot currently be exercised. Documented as unverified, not
  as behavior.

## Deliberately left open (need a live remote host)

- `job_status` runtime queries (`squeue`/`bjobs`/`qstat` parsing) —
  only the code path was read; no scheduler was available.
- `hold_dependencies` (job.rb:618) — code-read only.
- `scout batch list` performance summaries (`-BPP` Procpath,
  `-sacct`) — the CLI was exercised for `list`/`tail`/`clean --help`
  and for `tail`'s three resolution forms against a synthetic batch
  dir, but no Procpath/sacct output was produced.
- Actual `sbatch`/`bsub`/`qsub` submission, container/sync deployment
  (`contain`, `singularity*`) and offsite `deploy: <server>` dispatch —
  out of reach without a cluster.
