# Using the CLI

This document explains how the `scout` executable behaves: how it
dispatches to commands, which option forms every command accepts, and what
its exit codes mean. It is the reference for *the executable*; for the
library call that runs a job inside Ruby code see
[Building Workflows](BuildingWorkflows.md).

## What problem does this solve?

Workflows, entity properties, knowledge bases and resource production all
have to be reachable without writing Ruby. The `scout` executable is a
thin, uniform front end for all of them: one dispatcher
(`bin/scout`), one option-parsing convention shared by every command
(`SOPT`, from scout-essentials), and one help format. Learning the
convention once carries you through every command, including the
workflow-defined commands a workflow installs under its own
`share/scout_commands/`.

## When do I use it?

- Running a workflow job from the shell:
  `scout workflow task <workflow> <task> [inputs]`.
- Inspecting produced jobs: `scout workflow info/prov` on a step path.
- Listing what is installed: `scout workflow list`, `scout workflow cmd
  <workflow>` for workflow-local commands.
- Querying knowledge bases from the shell: the `scout kb` family —
  `register` adds a database, `entities` declares a type, `query` and
  `traverse` run the same queries as `KnowledgeBase#children` /
  `kb.traverse`, `show`/`list`/`config` inspect what is registered
  (all accept `-kb <name>` to select a knowledge base).
- Finding out which script a command really is: `--locate_file`.
- Managing jobs and caches: `scout system status/clean`, `scout purge`,
  `scout update` (`system status`/`clean` take a workflow and task name,
  or `.` for the current directory's job tree, and `clean` removes only
  jobs that are not `done` unless `--all`).

## Core concepts

### The dispatcher is a directory descent

`bin/scout` shifts words off `ARGV` and walks a tree rooted at
`Scout.scout_commands` — the `scout_commands/` directory of the
scout-gear installation in use, resolved through Scout's usual path
lookup:

```
scout_commands/
  workflow/        <- directory: consumed as a prefix, descent continues
    task           <- file: loaded as Ruby; the process ends there
  entity           <- file: a top-level command
  ...
```

- A word that names a **directory** is consumed as a prefix and the loop
  continues inside it.
- A word that names a **file** causes that file to be `load`ed; whatever
  the script does — including its exit status — is the whole command.
- A word that is an existing **filesystem path** is `load`ed directly
  (useful for `scout ./my_command.rb` style invocations).
- Anything else prints the usage for the deepest directory reached plus
  `Command '<word>' not understood`.

`~/.scout/scout_commands/` is part of that lookup, so dropping an
executable Ruby file there adds a top-level `scout <name>` command — the
top-level usage lists it as a subcommand.

The dispatcher itself has no `--help` word: `scout --help` (and
`scout workflow --help`, `scout batch --help` — any directory word) is
"`'--help'` not understood" (exit 255), exactly like any other unknown
word. Use `scout` with no arguments, or stop at a directory
(`scout workflow`, `scout batch`), to get usage; `--help` only means
"print help" once a command *file* has been reached, because it is one
of that file's own options.

`scout workflow task` therefore runs the file
`scout_commands/workflow/task`. The dispatcher is recursive: the `cmd`
subcommand re-implements the same descent inside the workflow's own
`<libdir>/share/scout_commands/` (shown by `scout workflow cmd
<workflow>`), so a workflow can ship its own command tree invoked
exactly like the built-ins. That tree is resolved relative to the
workflow's libdir, which is located from the workflow's `lib/`
directory — a workflow without one has no resolvable
`share/scout_commands/`.

### Pre-dispatch flags: processed by `bin/scout` itself

A small block of options is parsed by `bin/scout` *before* dispatch, and
is therefore available to every command — regardless of where it appears
on the command line, because two of them are stripped from `ARGV` by
literal scan before any library is loaded:

| Flag | Effect |
|---|---|
| `--nocolor` | Disables ANSI color. Stripped from `ARGV` and exported as `SCOUT_NOCOLOR` before any library loads, so it works even after the command name. |
| `--nobar` | Disables the progress bar (`SCOUT_NO_PROGRESS`), same early stripping. |
| `--log <level>` | Log severity 0 (debug) … 6 (errors). |
| `--dev <dir>` | Adds `<dir>/scout-*/lib` then `<dir>/rbbt*/lib` to the front of `$LOAD_PATH`, in that order. `--dev=<dir>` and the `SCOUT_DEV` environment variable are equivalent. |
| `--require <a,b>` | Comma-separated requires, each resolved as an absolute path, a `$LOAD_PATH` entry, or a plain script filename. |
| `-ck,--config_keys <spec>` | One or more config overrides, comma-separated. Each spec is a file, a profile in `etc/config_profile/`, or `key=value [token::priority]…`. |
| `--locate_file` | Print the resolved command script path instead of executing it. |

`--log`, `--dev`, `-ck/--config_keys` and `--locate_file` are parsed by
the `SOPT.setup` block in `bin/scout` itself and are removed from `ARGV`
there — before the dispatch loop — so they work wherever they appear,
including before the command word.

`SOPT` state is global to the process and *accumulates*: every command's
`SOPT.setup` adds to the block `bin/scout` already registered, so the
bin/scout flags also appear in every command's `--help` output above the
command's own options. For the CLI this is one setup per process and
therefore benign; library code that calls `SOPT.setup` more than once
inherits the earlier block's leftovers.

### Aliases

`Scout.etc.cmd_alias` (a yaml file) maps a short word to a command
prefix. If the first `ARGV` word matches an alias, it is replaced by the
tokenized alias value and the expansion repeats, so aliases can chain.
`scout alias` lists the configured ones (`alias: command…`, one per
line); `scout alias <name> <cmd>…` records one and `scout alias <name>`
with no command deletes it (both rewrite the whole yaml file). With no
such file the expansion loop is a no-op. `cmd_alias` runs before the
dispatch loop, so an alias stands in for the first words of any
invocation — `scout alias w workflow list`, then `scout w`, behaves
like `scout workflow list`.

### The command surface

The static tree shipped with scout-gear is 16 top-level commands
(`alias batch cat doc entity find glob kb log purge rbbt resource system
template update workflow`), five of which are directories with their own
subcommands:

| Family | Subcommands |
|---|---|
| `workflow` | `cmd example info install list process prov task trace write_info` |
| `batch` | `clean list tail` |
| `system` | `clean status` |
| `resource` | `produce sync` |
| `kb` | `config entities list query register show traverse` |

`scout entity <type> <property> <entity>` runs a single entity property:
the entity's declared attributes become flags, the property's own
parameters follow as positionals (a readable path is replaced by its
file's content; `true`/`false` and numbers are type-coerced), `-W`
loads the workflows that define the type (default `local`), and
`scout entity <type> --help` lists the available properties.

In the `workflow` family, `list` names the installed workflows and
`install <name…>` installs or updates them from their git source
(defaulting to `http://github.com/Rbbt-Workflows/`;
`SCOUT_WORKFLOW_AUTOINSTALL=true` makes missing workflows install on
demand). `info <step_path>` prints a job's info (add
`--inputs`/`--recursive_inputs` for its inputs), and `prov <step_path>`
prints provenance (`--plot <file.png>` draws the dependency graph;
`write_info <job> <key> <value>` annotates a job's info: the value is
written into the live `.info` file, re-writing the same key overwrites
it silently, and `--value nil` removes the key). Batch
execution semantics (`scout batch …`, `deploy` rules) are covered in
[HPC / Batch Execution](HPCBatchExecution.md); `scout workflow task` is
covered below. `scout resource produce <Resource> <file>` runs a
resource's `produce` block and prints the produced location (`-f`
forces it over an existing file), and `scout resource sync <path>
[<path_map>]` copies a produced path between path maps or hosts (`-s`
/ `-t` name source and target hosts, `-d` deletes source files).

The remaining top-level commands are one-file utilities:
`cat` prints and `find`/`glob` resolve Scout paths: a bare `<path>`
resolves through Scout's path maps (`scout find lib`), while
`<resource> <path>` first resolves `resource` as a workflow or a
constant (`scout find Scout scout_commands`) and looks the path up
under it; `--requires`/`--load_workflow` make extra resources
resolvable and `-w/--where` restricts the path map,
`log` prints or sets the global log severity
(`Scout.etc.log_severity`; a numeric argument is mapped to
`DEBUG…NONE`), `purge` lists or deletes files under a directory by
last access time (`--before <time>`, `--older <file>`, `--save <N>` to
keep the N most recently accessed; nothing is deleted without
`--delete`, and directories are never removed, so the cache layout
survives),
`update <gem>` runs `git pull` and `git submodule update` inside that
gem's checkout when it is an editable sibling (defaults to
`scout-essentials`), `template command` and
`template workflow.rb` emit skeletons. Substitutions are applied
textually everywhere they occur: a trailing `VAR=value` pair is read as
one (`template workflow.rb MODULE=MyMod` replaces the `MODULE`
placeholders), and `--sub VAR=value` / `--var VAR --value value` are the
flag forms; the `command` skeleton has none. `doc` prints a module's
markdown documentation from `Scout.doc.lib.scout`
(`~/.scout/doc/lib/scout/`, empty unless the documentation package is
installed; with no module it prints nothing and exits 0 when the
directory is empty — there is no listing — and a module that is not
there is a `NoMethodError` exit 255, not an empty result), and `rbbt`
re-enters the dispatcher
(`load Scout.bin.scout`), so it behaves like a second `scout` word
rather than a command of its own.

## The SOPT option convention

Every command file builds its options with `SOPT.setup <<EOF` and then
calls `SOPT.get` (directly, or via `Task#get_SOPT`). `SOPT` is a single
global registry: the pre-dispatch block described above stays registered,
and the command's own options are added to it. One consequence is worth
knowing: `SOPT` state is process-global and accumulates across `setup`
calls — benign for the CLI, where each command sets up once, but library
code that calls `SOPT.setup` more than once in a process inherits the
earlier inputs.

### Option forms

Given an input named `num` (non-boolean) and one named `flag`
(boolean):

- `--num=3` and `--num 3` are equivalent.
- Booleans are bare (`--flag` ⇒ `true`) or negated with
  `--flag=false`. A word *after* a bare boolean is **not** consumed as
  its value: it stays in `ARGV` as a positional — unless it is one of
  `F`, `false`, `FALSE`, `no`, which is then taken as the value (and a
  warning is logged).
- Unknown flags are consumed as positionals, not errors: `scout workflow
  task W t --stray` runs normally with `--stray` left in `ARGV`.
- `--` stops parsing; it and everything after it remain in `ARGV`.
- Repeated flags: the last occurrence wins.
- Shortcuts are derived automatically (`-n` for `num`, `-ck` for
  `config_keys`), extending to two or three letters when the first is
  taken (`-od` for `override_deps`).

### Array inputs and file detection

Inputs declared `:array` are the one place where the parser is clever,
and the rule matters:

- A comma list that does not name an existing file is split into its
  elements (`a,b,c` ⇒ `["a","b","c"]`).
- The *same* list when it does name an existing file is **not** split:
  it stays one whole `String` value.
- `-` means STDIN and is kept literally.

The rule is "does this string name a file?", so the same command line can
mean two different things depending on the filesystem: `--names a,b`
yields `["a","b"]` normally, but stays the single string `"a,b"` when a
file called `a,b` exists in the working directory. That whole-string case
is a hazard rather than a feature when the value is bound for a
non-`:array` input, or the reverse — for lists that are themselves file
paths, pass them as files (or through `--load_inputs`) rather than as
comma lists.

### Workflow task inputs

`scout workflow task <workflow> <task>` merges three sources:

1. The task's declared inputs, parsed from the remaining `ARGV` by
   `Task#get_SOPT` (`-n,--num=<type>` forms; `--help` prints the task's
   own usage including `Inputs` and `Returns:`).
2. `--load_inputs <dir-or-file>` — input files saved earlier with
   `--save_inputs <dir-or-tar.gz>` (merged over the flag values, so it
   wins for an input given on the command line).
3. `--override_deps <Workflow#task=path,…>` — dependency overrides,
   applied last, on top of both.

Job naming: **the first positional after the task name is not a
jobname** — `scout workflow task W t extra` still names the job
`Default`. Use `--jobname <name>`; otherwise the job id is the constant
`Default` (unless one input is declared `jobname: true`, in which case
that input's value names the job), with an input-derived hash suffix when
the inputs are not exactly the defaults.
`--printpath` prints the job path instead of the result;
`--clean`/`--recursive_clean`/`--clean_task <t>` re-run;
`--provenance` records provenance; `--exec`/`--fork` force the two
in-process execution modes; `--deploy <mode>` selects the deployment
route (`serial`, `local`, `workers`, `batch`/`sched`/`cluster`, or a
server name — see [HPC / Batch Execution](HPCBatchExecution.md)).

The full flag list is in `scout workflow task --help`; the notable ones
are `--update` (recompute when a dependency is newer), `--nostream`
(wait for the result rather than streaming it), and `--workflows <w,…>`
(load extra workflows so cross-workflow tasks resolve).

## Usage and help

- No arguments, or only options: the top-level usage (exit 0).
- `scout <cmd> --help`: a man-page-style header
  `scout <cmd>(1) -- <summary>` plus `SYNOPSYS`, `DESCRIPTION` and
  `OPTIONS`. (The `COMMANDS` subcommand listing is appended only by the
  *dispatcher* usage — no `ARGV` at all, or stopping at a directory —
  not by a command file's own `--help`.)
- `scout workflow task <workflow> --help` prints the command's usage plus
  the workflow's README documentation and its task list, then exits 0.
  Without a workflow name it stops at usage plus
  `Missing parameter 'workflow'` and exits 255.
  Adding a task name that the workflow does not have prints the workflow's
  documentation and its task list, then exits 255 (see the exit-code
  table). A `scout workflow task <workflow> <task> --help` where the task
  exists prints the task-level usage after the command's own option
  table: the task's own description, an `Inputs` table with types and
  defaults, `Inputs from dependencies:` sections labelled by the owning
  workflow, and a trailing `Returns: <type>`.
- `--locate_file` reports which script a command resolves to. It only
  takes effect once a command has been reached: before one, the
  top-level usage is printed instead.

Task help is generated from the declaration itself, so it always matches
the code: inputs appear with their declared types and defaults, inputs
provided by dependencies appear in an `Inputs from dependencies:`
section labelled by the owning workflow, and the `## TASKS` listing
shows exactly the exported tasks.

The workflow header and the per-task descriptions come from the
workflow's own `workflow.md` (or the libdir `README.md` when that file
does not exist), parsed into a title, a description paragraph and one
`## <task>` section per task. DSL `description`/`title` calls in
`workflow.rb` override the file only when the file does not exist. The
parse happens once and is cached in memory for the process, so editing
`workflow.md` while a `scout` process is alive does not refresh the
documentation it prints.

## Exit codes

| Situation | Exit | Output |
|---|---|---|
| No `ARGV`, or only pre-dispatch options | 0 | top-level usage |
| Stopping at a known directory (`scout workflow`, `scout batch`) | 0 | that directory's usage |
| `--help` on a command file (`scout entity --help`) | 0 | the command's man-page help |
| `scout workflow task <wf>` with `--help` but no task name | 0 | command usage + the workflow's documentation |
| `scout workflow task <wf> <missing-task>` | 255 | command usage + the workflow's documentation and task list (on stdout, no error text) |
| `scout workflow task` with no arguments at all | 255 | command usage plus `Missing parameter 'workflow'` |
| `--help` on the dispatcher itself (`scout --help`) | 255 | usage plus `Command '--help' not understood` |
| Unknown command, unknown workflow, unknown task | 255 | usage plus an `## ERROR` section |
| Command raised `ParameterException` (e.g. missing required input) | 255 | usage plus the message |
| Anything else raised | 255 | `Log.exception` backtrace |
| Normal completion | whatever the loaded script exits with, normally 0 |

The 255 comes from `exit -1`. Note that "usage" is the *narrow* case: a
word that is not in the deepest directory reached (`scout nosuchcmd`,
`scout --help`) is an error, while descending into a known directory and
stopping there (`scout workflow`) is usage.

## Common mistakes

- **Expecting `--flag value` to set a boolean.** It does not; the value
  stays in `ARGV` and may surface as an unexpected positional, *except*
  that the literal words `F`/`false`/`FALSE`/`no` are taken as the value
  (with a log warning). Use `--flag=false`.
- **Expecting an unknown flag to fail.** It is consumed as a positional
  and silently ignored by most commands.
- **Passing a literal comma list to a `:file` or `:string` input**
  expecting it to be split. Only `:array` inputs split, and only when
  the value does not name an existing file.
- **Putting `--jobname` first.** Positionals after the task name are not
  jobnames; the flag is required.
- **Relying on `--locate_file` before the command name.** Before any
  command word it prints the top-level usage instead of a path.

## Known breakage

Two `scout workflow` subcommands fail at `require` time in a stock
install. They are live defects, not contract behavior — recorded here
only so that the failure is recognizable; the fixes belong to the code,
not to this page:

- `scout workflow process` — `LoadError: cannot load such file --
  scout/workflow/deployment/orchestrator`. The option block never runs.
- `scout workflow trace` — `NoMethodError: undefined method 'var' for
  module Rbbt`, raised from rbbt-util while loading
  `rbbt/workflow/util/trace`. `--help` prints first, then the exception.

`scout workflow prov`, `info`, `task`, `install` and the rest of the
family work as described above. One further note that is not a load
failure: `example` requires a workflow argument (exit 255 without one,
`Missing parameter 'filename'`) and runs every example it finds under
the workflow's `examples/` directory — or just
`example <workflow> <task>` for one task — each in a forked child that
loads the `task` command from rbbt-util's own share directory with
`--load_inputs <example-dir> --jobname <name> -pf`. A workflow with no
examples under its libdir runs nothing and exits 0 silently. In a
scout-only install `Rbbt` is not defined, so the forked child fails;
the command then prints `ERROR <Wf>#<task> -- <name>` and `NO RESULT`
while still exiting 0. Treat its exit status as "every example was
attempted", not "every example passed".

## See also

- [Building Workflows](BuildingWorkflows.md) — the library API behind
  `scout workflow task`.
- [HPC / Batch Execution](HPCBatchExecution.md) — `scout batch` and the
  `--deploy` rules.
- [Cookbook](Cookbook.md) — recipes combining subsystems.
- Probe record: `research/cli-probes.md` (the consolidated investigation
  behind this page, non-normative).
