# Investigation: CLI — Probe Findings

> **Non-normative.** This document is a working investigation with
> implementation details, code exploration notes, and hypotheses. Refer
> to the authoritative doc (`doc/user/UsingTheCLI.md`) for the
> user-facing contract.

Findings from twelve probes run against `bin/scout`,
`scout_commands/**`, scout-essentials' `SOPT`, and the usage/help
generation in `lib/scout/workflow/usage.rb` during the
documentation-consolidation campaign. Each probe was executed through
`Observation/probe(<name>)` and its receipt cached. Claim identifiers
below refer to the Cortex artifact `scout-gear/cli.md` (map `current`,
21 claims / 12 receipts); full evidence chains, verbatim outputs and the
claim texts live there.

Re-verified against HEAD
`8a3a514d7200971179573a1e3808c1ba3bb9226c` ("Fixed issue loading step
paths", 2026-09-08), the same commit the claims artifact was verified
against; the promotion edits in this repo were also made at that HEAD.
Every behavior promoted into `doc/user/UsingTheCLI.md` was re-executed
against the live tree at promotion time (see "Round-trip caveats
re-verified at promotion time" at the end).

## Probe ledger

### `cli_dispatch_and_surface`

- **Probed**: the `bin/scout` dispatch loop, the static command surface,
  exit codes, and the `--locate_file` / `template` / `doc` corners.
- **Finding**: descent over `scout_commands/` with directories consumed
  as prefixes and files `load`ed; 16 top-level commands, 5 subcommand
  families; empty `ARGV` prints usage with exit 0. `--locate_file`
  before any command name prints usage, not a path.
- **Receipt**: `Observation/probe/cli_dispatch_and_surface_0d0d9c3737260738edac0c6b0087e48c.json`
- **Claims**: 1, 2, 3, 7, 8

### `cli_sopt_contract`

- **Probed**: `SOPT.setup`/`SOPT.get` semantics — registration, boolean
  and array forms, `--`, state across setups, synopsys rewriting.
- **Finding**: registration is global and accumulates across `setup`
  calls in one process; booleans do not consume a following word; `--`
  is retained in `ARGV`; comma values are split unless they name an
  existing file; a missing synopsys placeholder raises `IndexError`.
- **Receipt**: `Observation/probe/cli_sopt_contract_3ebda718809980d7037d726b518c2740.json`
- **Claims**: 9, 10, 11

### `cli_preprocess_flags`

- **Probed**: the pre-dispatch flag block in `bin/scout` (`--nocolor`,
  `--nobar`, `--dev`, `--require`, `-ck`, `--locate_file`).
- **Finding**: `--nocolor`/`--nobar` are stripped by literal `ARGV`
  scan before any library loads, so they work after the command name;
  `--dev` unshifts `scout-*/lib` then `rbbt*/lib`; `--require` resolves
  three ways; `-ck` is parsed by the same SOPT block the commands use.
- **Receipt**: `Observation/probe/cli_preprocess_flags_9192243b9bbc013506a58c438b050613.json`
- **Claims**: 3, 4

### `cli_prov_info_trace_surface`

- **Probed**: `scout workflow prov/info/trace` against a real job
  directory.
- **Finding**: `prov` and `prov --plot` succeed with non-empty output;
  `trace` dies at `NoMethodError … Rbbt` from the
  `rbbt/workflow/util/trace` require path; `info` dumps the step's
  `.info` fields.
- **Receipt**: `Observation/probe/cli_prov_info_trace_surface_23eac8747135086a8c06d332ff09e348.json`
- **Claims**: 6

### `cli_system_batch_groups`

- **Probed**: `scout system status`/`clean` and the `scout batch`
  command group's effect on the job tree.
- **Finding**: `system status` reports the job directories found;
  `system clean` removes only non-`done` ones; the `batch` group reads
  the batch directories written by the scheduler (see the deployment
  artifact for semantics).
- **Receipt**: `Observation/probe/cli_system_batch_groups_2da709b81d7f1ba43fb38e236b9c9040.json`
- **Claims**: 20

### `usage_export_surface`

- **Probed**: the `export`/`export_asynchronous`/`unexport` annotations
  and their effect on rendered usage.
- **Finding**: `export` and `export_asynchronous` are aliases appending
  to the same list (duplicates preserved); `## TASKS` lists exactly
  `all_exports`, so unexported tasks are hidden from help while still
  present in `tasks`.
- **Receipt**: `Observation/probe/usage_export_surface_f1fa6dd6ec2bc0221bdb0e95de9cbd55.json`
- **Claims**: 17

### `usage_sopt_setup_roundtrip`

- **Probed**: `Task#SOPT_str` / `Task#get_SOPT` /
  `Workflow.get_SOPT` round-trips over real `ARGV`.
- **Finding**: task-level strings render correctly including derived
  multi-letter shortcuts; parsing consumes `--num=3 --flag` and leaves
  positionals; array inputs accept comma lists and repeated flags (last
  wins); `:file` inputs are not read at parse time;
  `Workflow.get_SOPT` requires a registered workflow.
- **Receipt**: `Observation/probe/usage_sopt_setup_roundtrip_708d54f034b3cce7ba45115303d25669.json`
- **Claims**: 12

### `usage_sopt_str_bug_status`

- **Probed**: whether `Workflow#SOPT_str` is reachable and broken.
- **Finding**: it is broken in two ways (`nil`-shortcut `NoMethodError`
  and a `NameError` on `short`), but no in-repo caller exists and the
  CLI path does not go through it — latent for the shipped CLI, live for
  library users. Full statement in `scout-gear/workflow-engine.md`
  Claim 10; not re-derived here.
- **Receipt**: `Observation/probe/usage_sopt_str_bug_status_366e30a9aa316bf36051001677d67e03.json`
- **Claims**: 13 (cross-cite)

### `usage_task_help_generation`

- **Probed**: `Task#usage`, `Workflow#usage(task)` and
  `Workflow#usage`.
- **Finding**: task usage renders name, input table (types, defaults,
  select options) and `Returns:`; workflow usage wraps it under a
  README-derived header, adds an `Inputs from dependencies:` section
  labelled by the owning workflow and a `## DEPENDENCY GRAPH` block;
  `usage()` with no task renders README + `## TASKS`, while `usage(true)`
  raises `TaskNotFound`.
- **Receipt**: `Observation/probe/usage_task_help_generation_6d9493578c76b0acf5bfd1c83dc63cf4.json`
- **Claims**: 14, 15, 16

### `workflow_docs_generation`

- **Probed**: `Workflow#documentation` parsing of `workflow.md`/README
  and the DSL `description`/`title` overrides.
- **Finding**: a `workflow.md` or README under the workflow's libdir
  wins; the DSL setters only apply when no such file exists; task
  descriptions come through `doc_parse_first_line`.
- **Receipt**: `Observation/probe/workflow_docs_generation_7b98ec6d68c25b91f30f4bdd4f33bf27.json`
- **Claims**: 18, 19

### `cli_command_smoke` *(new in this batch)*

- **Probed**: uniform `--help` / exit-code surface over all 31 commands
  (15 top-level + families), plus `scout alias`. Consolidation-time
  re-count at the same HEAD: `scout_commands/` holds 16 entries (the
  claim's 15 plus `batch`, which the claim's own family table already
  covers), and the dispatcher's `## COMMANDS` listing shows all 16.
- **Finding**: every probed invocation prints a man-page header and
  exits 0 except the two load failures below and `scout rbbt`, which
  has no `--help` handling of its own (it forwards to rbbt-util).
  `scout alias` prints the `scout alias(1)` header.
- **Receipt**: `Observation/probe/cli_command_smoke_0821acf45703f7a32f99a79b5db6e491.json`
- **Claims**: 5, 6, 21

### `cli_process_trace_broken_commands` *(new in this batch)*

- **Probed**: the two `scout workflow` subcommands that fail at
  `require` time, isolated to the require level in a clean HOME and
  against both repo and installed gem.
- **Finding**: `process` → `LoadError … deployment/orchestrator` (the
  repo ships `orchestrator/` as a directory, no `orchestrator.rb`);
  `trace` → `NoMethodError … Rbbt` from rbbt-util's `R/model.rb`.
- **Receipt**: `Observation/probe/cli_process_trace_broken_commands_85ed34c1130d05f565a61fdc3f3170ed.json`
- **Claims**: 6

## Consolidated observations

1. **The dispatcher is three loops, not one.** `bin/scout` walks its own
   `scout_commands/` tree; `scout_commands/workflow/cmd` re-implements
   the same descent inside `<workflow>/share/scout_commands/`; and
   `scout_commands/workflow/example` re-enters through a forked
   `load` of rbbt-util's `task` command. All three share `SOPT` state,
   which is why the pre-dispatch block is visible in every one of
   them. *(1, 4, 9; the `example` half refined at promotion time — see
   observation 6)*
2. **"Usage wanted" vs "unknown" is the only exit-code distinction.**
   Everything that is not a successful run or a wanted usage is
   `exit -1` ⇒ 255. Which of the two a word falls into depends on
   whether the deepest directory reached contains it, which is why
   `scout workflow` is usage (0) while `scout workflow task NoSuchWF t`
   is an error (255). *(2, 6)*
3. **SOPT's file detection is the load-bearing subtlety.** An `:array`
   value that names an existing file is passed through whole by SOPT;
   `Task#get_SOPT` then splits array values *only when they do not name
   an existing file* (`usage.rb:115-123`). Promotion-time re-verification
   corrected the claim that the second pass splits on newlines: there is
   no `\n` split anywhere in this path, so a one-per-line file passed as
   `--names <file>` reaches the task as a single whole element. The
   double "is it a file?" test is what makes `--names a,b` and
   `--names <a file named a,b>` differ, and it is the hazard worth
   remembering. *(10, 12)*
4. **Help is generated, never maintained by hand.** Task input tables,
   dependency-input sections, select options and the `## TASKS` listing
   are all derived from the declarations, so `--help` cannot drift from
   the code. The flip side is that the annotation surface is list
   bookkeeping: `export` only controls listing. *(14-17)*
5. **Two subcommands cannot load at all.** `process` and `trace` fail
   during `require`, before their option blocks run, so no flag can work
   around them. Both are repo-level defects, not CLI-contract issues.
   *(6)*
6. **`example` is a rbbt-util shim that cannot work scout-only.** It
   forks and loads `Rbbt.share.rbbt_commands.workflow.task.find`
   (`example:48-49`), so without rbbt-util on the load path the child
   fails before running anything, while the parent exits 0. A third
   dispatcher-shaped command, but a broken one in this install. *(7
   neighborhood; promotion-time finding)*

## Improvement candidates (defects, not documented as normal behavior)

- `scout workflow process` cannot load: the command requires
  `scout/workflow/deployment/orchestrator`, but the repo ships
  `lib/scout/workflow/deployment/orchestrator/` (a directory with
  `batches.rb chains.rb rules.rb workload.rb`) and no `orchestrator.rb`.
  HPCBatchExecution.md's documented entry point is therefore dead.
  *(6)*
- `scout workflow trace` cannot load: `NoMethodError … Rbbt` raised from
  rbbt-util's `R/model.rb` while requiring
  `rbbt/workflow/util/trace`. *(6)*
- `scout doc <module>` crashes with `NoMethodError: undefined method
  'read' for nil` — the command assumes a doc-dir layout the repo does
  not provide; with no module it is silent and exits 0. *(7)*
- `scout workflow example` depends on rbbt-util's `Rbbt` constant at
  run time (see the promotion-time caveat below), so on a scout-only
  install it cannot execute an example and still exits 0. *(7
  neighborhood; promotion-time finding)*
- `scout template` substitution is a plain `String#gsub!(key, value)`
  over the skeleton, so any positional whose left side matches *any*
  substring rewrites it — including `MODULE=X`, which works as
  advertised but also fires on words that were never meant as
  placeholders. *(7)*
- `SOPT` state is global and accumulates across `setup` calls in one
  process; benign for the CLI, a trap for library users. *(9)*
- `Workflow#SOPT_str` is broken two ways (`NoMethodError` /
  `NameError`); unreachable from the CLI, no in-repo callers. *(13,
  cross-cite to `scout-gear/workflow-engine.md` Claim 10)*
- `scout workflow task` with no `ARGV` and `--help` on an unknown task
  print a full `## ERROR` section with a backtrace where a one-line
  message would do. *(2, 21)*
- A workflow-local command tree silently disappears when the workflow
  has no `lib/` directory (see the promotion-time caveat below): the
  libdir resolves to `/`, `scout workflow cmd <Wf>` lists nothing, and
  the subcommands report `Command not understood`. No probe covers it
  because no probed workflow lacked a `lib/`.

These belong in `Improvements.md`, not in the user/developer docs. The
first two (`process`, `trace`) are also noted on the deployment owner's
page (`research/deployment-hpc-probes.md`, "Improvement candidates"),
which exercises them through the scheduler entry point; the CLI-side
note is kept here because the failure surfaces at the `require` in
`scout_commands/workflow/{process,trace}`.

---

## Round-trip caveats re-verified at promotion time

Every statement promoted into `doc/user/UsingTheCLI.md` was re-executed
against the live tree (`HOME` set to a scratch directory, `ruby
bin/scout …` from the repo root) before writing the page. Two items
needed wording corrections relative to the probe-era summaries in the
claims artifact, two further items are promotion-time discoveries rather
than claim corrections, and one benign case was folded into the page
rather than listed here:

- **There is no newline split for array inputs.** SOPT keeps a comma
  value whole when it names an existing file; `Task#get_SOPT` then
  splits an array input only `unless Open.exist?(value)` or the type is
  file/path-like (`lib/scout/workflow/usage.rb:115-123`). The claims
  artifact (Claim 10) and the earlier draft of this note described a
  newline split in the second layer; re-testing through the actual CLI
  (`--names <one-per-line file>` ⇒ one *whole* element, `n=1`, with the
  file contents intact inside that element) shows no `\n` split exists
  anywhere on this path. Consequence: a list file must be passed via
  `--load_inputs` (which writes one file per input) rather than as an
  `--names <file>` value. The claims artifact's latent-`TypeError`
  wording for string-typed inputs is likewise a task-declaration
  concern, not a parser behavior; the doc page documents the mechanism.
- **`scout workflow task` with no arguments exits 255, not 0.** The
  claims artifact (Claim 2) records `scout workflow task` with no task
  as a usage/0 case. Live code at this HEAD raises
  `MissingParameterException` (`workflow` is nil) *before* the help
  branch — `scout_commands/workflow/task:37` assigns
  `workflow_name, task_name = ARGV` and line 44 raises immediately when
  `workflow_name` is nil, whereas the artifact's HEAD had the help
  branch first. What *does* exit 0 is `scout workflow task <wf> --help`
  (a workflow, no task): usage plus the workflow documentation. The doc
  page's exit-code table records both rows separately.
- **`scout workflow example` never surfaces its failures through the
  exit status, and in a scout-only install it cannot run an example at
  all.** The command forks, redirects the child's stdout to a scratch
  file and `load`s `Rbbt.share.rbbt_commands.workflow.task.find`
  (`scout_commands/workflow/example:48-49`) — `Rbbt` is not defined
  when only scout-gear and scout-essentials are loaded, so the child
  dies and the parent reports `ERROR <Wf>#<task>` plus `NO RESULT`
  while still exiting 0. The claims artifact (Claim 7's neighborhood)
  recorded only the silent-exit-0 half; the `Rbbt` dependency is a
  promotion-time finding. The doc page describes it as a known-issue
  note, not as contract behavior.
- **A workflow-local command tree needs a `lib/` directory.**
  `scout_commands/workflow/cmd` resolves
  `wf.libdir.share.scout_commands` where `libdir` comes from
  `Path.caller_lib_dir` at `extend Workflow` time
  (`lib/scout/workflow.rb:63-69`). A workflow installed under
  `~/.scout/workflows/<Wf>/` *without* a `lib/` directory gets a libdir
  of `/`, so `scout workflow cmd <Wf>` lists nothing and every
  subcommand falls through to `Command not understood` — even though
  the `share/scout_commands/` files are present. Adding an empty
  `lib/` fixes it. Discovered while re-verifying the `cmd` descent
  with a hand-built workflow; no probe covers it. A final, benign
  case re-run at promotion time: `example <workflow>` with no examples
  installed runs nothing and exits 0 — folded into the page's `example`
  note rather than listed as a divergence.

No other promoted statement diverged from the live tree. The
`task`-with-no-args divergence above is a genuine behavior change
between the probe-era tree and this HEAD, not a transcription error;
it was re-run three times (scratch `HOME`, repo root, and with
`--help`) before being written down.
