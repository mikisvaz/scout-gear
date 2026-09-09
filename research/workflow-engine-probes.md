# Investigation: Workflow Engine — Probe Findings

> **Non-normative.** This document is a working investigation with
implementation details, code exploration notes, and hypotheses. Refer
to `doc/user/` and `doc/developer/` for maintained documentation.

Consolidated record of the twelve probe artifacts (one covers two legs of
the same investigation, so there are thirteen ledger sections) run against
the workflow engine
layer (`lib/scout/workflow.rb`, `workflow/definition.rb`,
`workflow/task.rb` + `task/{dependencies,inputs,info}.rb`,
`workflow/step.rb` + `step/{archive,children,config,dependencies,file,
info,inputs,load,progress,provenance,status}.rb`, `workflow/usage.rb`)
during the documentation-consolidation campaign. Each probe was executed
through `Observation/probe(<name>)` and its receipt cached; claim
identifiers below refer to the Cortex artifact
`scout-gear/workflow-engine.md` (map `current`), which holds the full
evidence chains. Deployment/HPC runtime behaviour is Deployment's scope.

All probes ran in a plain Ruby environment, deterministic and
single-process, each standalone under `timeout 60`. The behaviors were
re-verified against HEAD `8a3a514d7200971179573a1e3808c1ba3bb9226c`
(unchanged during promotion) before promotion into
`doc/user/BuildingWorkflows.md`, `doc/user/Cookbook.md` and
`doc/developer/WorkflowEngine.md`.

---

## Summary of findings

1. **Task blocks receive only their own declared inputs, positionally.**
   A block with fewer parameters silently drops extras; a one-parameter
   block gets the first input; a zero-parameter block gets `nil`; keyword
   arguments are not supported. There is no `input[...]` accessor in the
   execution context (C02, C03, C11).

2. **`input` annotates the next task only.** Inputs declared between two
   tasks belong to the second task; later tasks get none (C11).

3. **The job digest uses non-default inputs only and is
   order-independent.** Passing an input's own default yields the same
   path as omitting it (`Default`); any non-default value appends
   `_<md5>`; swapping two non-default inputs does not change the digest
   (C06).

4. **`workflow.job` memoizes Steps.** The same task/id/input signature
   returns the same object (`.equal? == true`); different inputs give
   different objects (C06).

5. **`compute: false` means "do not force or wait", not "do not run".**
   The dependency stays in the dependency list, is consumed if its result
   is on disk, and is simply left absent otherwise; the parent still
   completes (C05, C04).

6. **`compute: :canfail` leaves a visible failure.** The dep keeps
   `status == :error`, `dep.load` raises the stored exception, the parent
   block still receives `nil` (C04).

7. **A step with no `.info` reports `status == ""`.** Not `waiting`.
   Most predicates are false, `updated?` is true, `running?` is `nil`
   (C01). `error?` and `running?` can both be true for an errored step
   whose PID is still alive (C01).

8. **`.info[:dependencies]` records the direct level only.** Deep chains
   must be walked from disk; in-memory `rec_dependencies` resolves them
   (C08).

9. **`task_alias` is a real task with its own directory.** `alias.load`
   equals the producer's result, but the alias path differs from the
   producer's path (C07).

10. **Cross-workflow `dep` and `include_workflow` keep the producer's
    ownership.** The dep Step resolves into the producer workflow's task
    directory, records that path in the consumer's `.info`, and the
    producer's job-path digest participates in the consumer's digest
    (C12, C13).

11. **Remote steps are `OffsiteStep` annotations, not a foreign class.**
    scout-camp annotates the same `Step` object; scout-gear's
    `RemoteStep` guard in `include_workflow` is dead code here (C14).

12. **`Resource.identify` is the local/remote path denominator.**
    Absolute → `var/...` relative → back through `find(:user)`; `Step.load`
    uses this round-trip to read results produced under another `var`
    root (C15).

---

## Probe ledger

### `wf_input_access`

Probed input access inside task blocks: positional vs keyword block
parameters, block arity vs input count, and the (non-existent)
`input[...]` idiom.

Finding: block parameters receive only the task's own declared inputs, in
declaration order with defaults applied; fewer parameters silently drop
extras, a single parameter gets the first input, zero parameters get
`nil`, and keyword arguments raise `ArgumentError`. There is no
`input[...]` accessor in the execution context.

- Receipt: `Observation/probe/wf_input_access_6ed4062f2740266c25d6e9fed236700d.json`
- Claims: C02

### `wf_status_transitions`

Probed the on-disk status lifecycle and every predicate against it,
including the degenerate states (no `.info` file, cleaned step, errored
step with a live PID).

Finding: `status` is `""` when no `.info` exists; `updated?` is then
`true` and `running?` is `nil`; `clean` restores exactly that state;
`:queue` is written only by the forked child path. `init_info` writes the
full input/dependency bookkeeping; a completed run adds timings and PID;
an error run keeps `status: error` plus the encoded exception.

- Receipt: `Observation/probe/wf_status_transitions_0dbf82d84ccc2c1edf7991841944e099.json`
- Claims: C01

### `wf_dep_mechanics`

Probed dependency instantiation and failure handling: how deps appear in
`Step#dependencies`, how `compute:` options are collected, what the parent
block receives, and the erroring-dep cases with and without
`compute: :canfail`.

Finding: `Task#dependencies` builds a compute map keyed by the dep's
absolute path with stringified option lists; the parent block receives
`nil` for a dep it does not re-declare as an input; `.info[:dependencies]`
holds paths. Without `:canfail` the parent errors; with `:canfail` it
completes while the dep keeps `status == :error`, `dep.load` raises the
stored exception, and the parent block still sees `nil`.

- Receipt: `Observation/probe/wf_dep_mechanics_4f44a9d24bcaad378d0e7680cc9caf78.json`
- Claims: C03, C04

### `wf_compute_false_semantics`

Probed `dep :t, compute: false` across the states that matter: dep absent,
dep already done, dep cleaned then parent re-run.

Finding: the run/wait loop is skipped for that dep
(`compute_options.include?(false)`), but the dep stays in the dependency
list, is consumed when its result exists, and is left absent otherwise;
the parent completes in every case.

- Receipt: `Observation/probe/wf_compute_false_semantics_3e0c098d89e9b05c7954ef28f113b6bd.json`
- Claims: C05

### `wf_skip_and_alias`

Probed `task_alias` shape: alias task name, `alias?`, its own job
directory, its dependency on the original, and how a consumer sees it.

Finding: the alias is a distinct task (`alias? == true` on Task and on
the dep Step a consumer gets) whose own path lives under the alias name;
it joins the original before finishing, so `alias.load` equals the
producer's result while the two paths differ.

- Receipt: `Observation/probe/wf_skip_and_alias_eea33c922c5c1e0e8277bc9da9f91a39.json`
- Claims: C07

### `wf_task_definitions`

Probed task annotations and declaration mechanics: `name`, `type`,
`n_inputs`, `deps`, `directory` (a String at definition time),
`description`, `returns`, `extension`, `task_signature`, helper
availability, and repeated input declaration.

Finding: annotations are attached by `annotate_next_task` and consumed by
the next `task` call; a repeated `input` on one task does not duplicate
`task.inputs`; `recursive_inputs` duplicates dep inputs per level when
re-declared, which is what `Workflow#usage` prints.

- Receipt: `Observation/probe/wf_task_definitions_a65c934c5adc6b9d88853c80f1ab2338.json`
- Claims: C11, C03

### `wf_job_path_digest`

Probed the job-path digest and `workflow.job` memoization: defaults
passed explicitly, non-default values, argument order, explicit job id.

Finding: only non-default inputs enter the digest; the digest is
order-independent; `job(:t, b: 3)` == `job(:t)` == `Default`;
`job(:t, "Hsa")` == `Hsa`; repeated identical calls return the same Step
object.

- Receipt: `Observation/probe/wf_job_path_digest_130260b901a05fe78afe0d8273cb02f3.json`
- Claims: C06

### `wf_provenance_chain`

Probed what a three-level chain (`top → mid → base`) records on disk and
what the in-memory view offers.

Finding: `top.info[:dependencies]` names only `mid`; a cold reload of
`top` reconstructs only that direct level; `rec_dependencies` resolves
the full chain in memory; `provenance` reports all three.

- Receipt: `Observation/probe/wf_provenance_chain_9bc3a2ccc913a5f47386986b3fa5c192.json`
- Claims: C08

### `wf_step_files_and_load`

Probed result storage and loading per documented type, plus `.files`,
`no_load` runs, and the result-without-info case.

Finding: `load` returns the type-deserialized result (`:string` → String,
`:tsv` → TSV-backed Hash, etc.); `file`/`files`/`files_dir` manage
`<path>.files/`; a result file without `.info` still loads and reports
`done?`/`updated?` true with `status == ""`.

- Receipt: `Observation/probe/wf_step_files_and_load_d6bbbdc180b6f97630d6183ea7e93364.json`
- Claims: C09, C01

### `wf_exports_usage_docs`

Probed `export` and its `asynchronous`/`synchronous`/`exec`/`stream`
variants, including repeated declarations and task-argument forms.

Finding: `export :t1, :t2` appends to `asynchronous_exports` in order;
the variants alias to the same method with a mode argument; included
workflows merge their export lists.

- Receipt: `Observation/probe/wf_exports_usage_docs_f18d85298d5361b05b63aff4ce8c5327.json`
- Claims: C10, C13

### `wf_cross_workflow_dep`

Probed `dep OtherWorkflow, :task` end to end: paths, signatures,
`info[:workflow]`, and the producer's input reaching the consumer's
digest.

Finding: the consumer's dep Step resolves to the producer's task
directory and records that path; the producer's digest participates in
the consumer's (changing the producer's input changes the consumer's
path); the consumer's `recursive_inputs` exposes the producer's input.

- Receipt: `Observation/probe/wf_cross_workflow_dep_37f746c4c98d8ce5737dc419d4e6c1a3.json`
- Claims: C12

### `wf_cross_workflow_dep` (include_workflow leg)

Probed `include_workflow` within the same cross-workflow setup: task
sets, directories, signatures, `info[:workflow]`, Step workflow objects,
helper availability, export list merging.

Finding: included tasks are borrowed, not relocated — each keeps the
producer's directory, `task_signature`, `info[:workflow]` and Step
workflow; helpers become available; export lists merge. Jobs for included
tasks land in the producer's own job directory.

- Receipt: `Observation/probe/wf_cross_workflow_dep_37f746c4c98d8ce5737dc419d4e6c1a3.json`
- Claims: C13

### `wf_remote_step_api`

Probed the scout-camp `OffsiteStep` surface from scout-gear (requiring
`scout/offsite/step`, annotating a local Step, the resulting method list,
the absence of any `RemoteStep` class, and what happens with no reachable
host), plus the identify/find round-trip that underpins local/remote
result interoperability.

Finding: `OffsiteStep.setup(job, server: ...)` annotates the very same
`Step` (`equal?` true, still `is_a?(Step)`, path and `task_signature`
unchanged), adding `run`, `done?`, `exec`, `info`, `orchestrate_batch`,
`offsite_path`, `inputs_directory` and the annotations `server`,
`workflow_name`, `clean_id`, `batch`. With no reachable host, local file calls
short-circuit on the local path while every wire-bound call raises
`Socket::ResolutionError` (a transport error, no Scout-specific rescue);
`server: "localhost"` special-cases to `SSHLine::Mock`. No `RemoteStep`
class is defined by scout-gear or scout-camp 0.2.0, so the
`defined?(RemoteStep) && RemoteStep === dep` guard in `include_workflow`
cannot fire here. Path identity rests on `Resource.identify`: the absolute
path identifies to the `var/...` relative String, `Path#find(:user)` maps
it back to the same file, and `Step.load` accepts either form — the same
path is shared by the local and the offsite Step of one task; only the
production site differs.

- Receipt: `Observation/probe/wf_remote_step_api_1394e816dd91f784261e88f2e2cf89a7.json`
- Claims: C14, C15

---

## Consolidated observations

**Inputs, blocks, and the digest form one contract.** The three probes on
task definition, dep mechanics, and the digest show a single design: a
task owns exactly the inputs declared immediately before it; the block is
called with those inputs positionally and nothing else; everything the
job depends on that is not an own-input default is folded into the path
digest (own non-default inputs, dependency signatures, and — through
those signatures — the producer's digest in the cross-workflow case).

**`compute:` options are an execution policy, not a graph edit.** No
`compute:` value removes a dependency from the graph or from
`.info[:dependencies]`; they only change whether the run/wait loop forces
and awaits it. `false` defers to whatever is on disk; `:canfail` keeps
the failure visible instead of propagating it; `:produce`/`:stream`
control result materialization.

**Ownership of a result never moves.** `include_workflow`,
`dep OtherWorkflow, :task`, and `task_alias` all reuse results in place:
the producer's directory and `info[:workflow]` are authoritative, and only
`task_alias` introduces a genuinely new directory (under the alias name)
that itself joins the original. This is what makes the digest chain
across workflows sound: a consumer's path already encodes where its
inputs were actually computed.

**Status is a pair of files, not a variable.** Predicates are derived
from two independent facts — result file existence and `.info` content —
and the interesting edge cases (missing `.info`, missing result,
errored-but-alive PID) are exactly the combinations where the two
disagree. Reading `status` alone is not enough to decide whether a step
ran.

---

## Improvement candidates (defects, not documented as normal behavior)

- `Workflow#SOPT_str` (module form, `usage.rb:103`) references a local
  that is never assigned (the working `SOPT_str(task)` form assigns
  `shortcut`) and raises `NameError` for any workflow with inputs; the
  no-task `Workflow#get_SOPT` (`usage.rb:115`) calls it and inherits the
  same `NameError`. `Workflow#SOPT_str(task)` (`usage.rb:315`) itself
  works for existing tasks but raises `NoMethodError: undefined method
  'recursive_inputs' for nil` when the task is absent from `self.tasks`
  (nil lookup); `get_SOPT(task)` (`usage.rb:327`) delegates to it. Claim 10.
- `cleaned_dependencies` (`workflow/step/status.rb`) always returns `[]`.
- The `RemoteStep` branch in `include_workflow`
  (`workflow/definition.rb:212`) is unreachable dead code in this
  repository.

These belong in `Improvements.md`, not in the user/developer docs.

---

## Deliberately left open

- **Result sync-back, `orchestrate_batch`, `hold_dependencies`**: these
  require a reachable remote host; the probes could not execute them.
  Only the receipted API surface and the code path were recorded. The
  runtime/cluster side is Deployment's scope
  (`research/deployment-hpc-probes.md`).
- **`:queue` status semantics**: written only by the forked child path;
  recorded from code reading, not exercised by a single-process probe.
- **`require_workflow`'s install/network fallback**: exercised standalone
  in this environment but not receipted through `Observation/probe`; see
  the claims artifact for the exact qualification.
