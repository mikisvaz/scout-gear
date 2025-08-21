# Workflow

The Workflow module implements a lightweight, annotation-based workflow engine. It lets you:

- Define workflows composed of named tasks with typed inputs, defaults and dependencies.
- Instantiate jobs (Steps), run them synchronously or as streams, track provenance, and persist results atomically.
- Override dependencies, archive inputs/outputs, and relocate jobs across path maps.
- Orchestrate multiple jobs under resource constraints.
- Attach helper methods to workflows and reuse them in task code.
- Generate usage and task documentation automatically.
- Extend workflows with entity-oriented helpers (EntityWorkflow).

It integrates with core modules: Annotation, IndiferentHash, Path, Open, Persist, Log, ConcurrentStream, and SOPT.

Sections:
- Defining workflows and helpers
- Inputs, tasks and dependencies
- Jobs (Step): execution, streaming, info, files, provenance
- Orchestrator: scheduling with resource rules
- Task aliases and overrides
- Usage and documentation
- Entity workflows
- Persist helper
- Path integration (step files)
- Queue helpers
- API quick reference
- CLI: scout workflow commands
- Examples

---

## Defining workflows and helpers

Create a module and extend Workflow. Set a name (used in job storage paths and provenance). Optionally add helper methods reusable in tasks:

```ruby
module Baking
  extend Workflow
  self.name = "Baking"

  helper :whisk do |eggs|
    "Whisking eggs from #{eggs}"
  end

  helper :mix do |base, mixer|
    "Mixing base (#{base}) with mixer (#{mixer})"
  end

  helper :bake do |batter|
    "Baking batter (#{batter})"
  end
end
```

Helpers:
- Define with `helper :name { ... }` to register.
- Invoke inside tasks simply as method calls.
- Outside task contexts, call `workflow.helper(:name, args...)`.

Directory:
- `Workflow.directory` defaults to Path "var/jobs".
- Each workflow has a per-name subdir: `workflow.directory # => var/jobs/<WorkflowName>`.
- Set it via `workflow.directory = Path.setup("tmp/var/jobs/<name>")`.

Anonymous workflows:
```ruby
wf = Workflow.annonymous_workflow "MyWF" do
  input :string, :string
  task :length => :integer do |s|
    s.length
  end
end
```

---

## Inputs, tasks and dependencies

Inputs are declared before tasks:

```ruby
input :name, :string, "Name to call", nil, jobname: true
input :count, :integer, "Times", 1, required: false
```

- Signature: input(name, type = nil, [description], [default], [options = {}])
- Common options:
  - jobname: true — this input sets the job identifier if provided.
  - required: true — missing or nil values raise ParameterException.
  - shortcut — preferred CLI short option letter (SOPT).

Task definitions:

```ruby
task :call_name => :string do |name|
  "Hi #{name}"
end
```

- Signature: task(name_and_type, &block)
  - name_and_type can be Hash ({name => type}), Symbol/String (defaults to :binary).
  - Supported types: :string, :integer, :float, :boolean, :array, :yaml, :json, :marshal, :tsv, :binary, etc.
- Implicit inputs: the block parameters match declared inputs in order.
- Description and metadata:
  - desc "..." — description shown in usage.
  - returns(type) — annotate return type (already in the task type).
  - extension("ext" or :dep_task) — filename extension for jobs of this task. When :dep_task, extension is inferred from aliased dependency.

Dependencies:

```ruby
dep :prepare_batter
dep :whisk_eggs
task :bake_muffin_tray => :string do 
  bake(step(:prepare_batter).load)
end
```

- dep signatures:
  - dep(workflow, task, options = {}, &block)
  - dep(task, options = {}, &block) — workflow self
  - dep({ ... }) — pass only options
- Options map dependency inputs and behavior:
  - Symbols reference previous dependencies or provided inputs by name.
  - :jobname to set child jobname; `jobname: nil` to reset and use parent id where applicable.
  - :compute flags: :canfail, :stream, :produce (also available at top level via block return).
- Block form receives `(jobname, options, dependencies)` and returns:
  - Step — explicit dep
  - Hash — merged into options (keys: :inputs, :jobname, :compute, :produce, :stream, :canfail)
  - Array of Hash/Step — multiple deps

Dependency input resolution:
- Symbol value v in options tries, in order: a dep with name v, a provided input v, or the current options[v].

Recursive inputs and overrides:
- `task.recursive_inputs` merges required inputs from its dep tree, honoring local overrides.
- Override any dependency at job instantiation using keys "Workflow#task" => step_or_path:
  ```ruby
  base = wf.job(:step1, input1: 6)
  job  = wf.job(:step2, "Workflow#step1" => base)
  ```

---

## Jobs (Step)

Create jobs from tasks:

```ruby
job = wf.job(:call_name, "Miguel")             # jobname from jobname input
job = wf.job(:call_name, nil, name: "Cleia")   # pass inputs explicitly
```

Step basics:
- `step.run(stream = false | :no_load | :stream)`:
  - false (default): computes and returns the Ruby object (non-streaming) or stored result if present.
  - true or :stream: run and return a streaming IO; producer is a ConcurrentStream; join or read to EOF to finish.
  - :no_load: run but return nil (useful when only persisting).
- `step.exec`: execute task block directly in-process without persistence (converts child Step return types if needed).
- `step.join`: wait for completion and raise on error; re-raises job exception from info.
- `step.path`: persisted path (Path or String).
- `step.files_dir`: companion directory `<path>.files` holding auxiliary files.
- `step.file("name")`: file helper within files_dir.
- `step.info`: IndiferentHash with status, pid, start/end times, messages, inputs, dependencies, etc. Stored at `<path>.info` (JSON by default).
- `step.log(status, [message_or_block])`: set info status and message (block timed).
- Status helpers: `done?`, `error?`, `aborted?`, `running?`, `waiting?`, `updated?`, `dirty?`, `started?`, `recoverable_error?`.
- Cleanup: `clean`, `recursive_clean`, `produce(with_fork: false)`.
- Dependency helpers: `dependencies`, `input_dependencies` (Steps in inputs), `rec_dependencies(connected=false)`.
- Provenance: `Step.prov_report(step)` returns colorized tree as text.
- Progress: `progress_bar(desc, options) { |bar| ... }`; `traverse(obj, desc:, **kwargs, &block)` integrates TSV.traverse with a bar.
- Child processes and commands:
  - `child { ... }` — fork a child process and track pid in info[:children_pids].
  - `cmd("shell args", log:, pipe: true, ...)` — run external command streaming stdout into process logs; ties child pid to this step.

Streaming pipelines:
- If a dep is marked for streaming (compute includes :stream) and SCOUT_EXPLICIT_STREAMING is set, you can consume child streams while they are produced.
- `step.stream` returns the next available stream copy; reading to EOF auto-joins producers (ConcurrentStream autojoin if set).
- `consume_all_streams` drains internal tees when streaming.

Saving and loading inputs:
- `task.save_inputs(dir, provided_inputs)` writes inputs to files (including file/array/file_array handling).
- `task.load_inputs(dir)` reconstructs input hash; supports .as_file/.as_path/.as_step markers and tar.gz bundles (auto-extracted).
- `step.save_inputs(dir_or_tar_gz_path)` convenience to export job inputs; `save_input_bundle` writes a tarball.

Archiving:
- `step.archive_deps` stores dependency info/inputs under `info[:archived_info]` and `info[:archived_dependencies]`.
- `step.archived_info`/`step.archived_inputs` read back archived data.

Relocation:
- `Step.load(path)` reconstructs a job, relocating to alternative maps if necessary (Path.relocate heuristics, including var/jobs/<wf>/<task>/...).

---

## Orchestrator: scheduling with resource rules

Workflow::Orchestrator runs sets of jobs respecting resource constraints (cpus, IO, etc.) with periodic scheduling:

```ruby
rules = YAML.load <<-YAML
defaults:
  log: 4
default_resources:
  IO: 1
MyWF:
  a: { resources: { cpus: 7 } }
  b: { resources: { cpus: 2 } }
  c: { resources: { cpus: 10 } }
  d: { resources: { cpus: 15 } }
YAML

orchestrator = Workflow::Orchestrator.new(0.1, "cpus" => 30, "IO" => 10)
orchestrator.process(rules, jobs)
```

Features:
- Builds a workload graph from jobs and their dependencies (including input_dependencies).
- Selects runnable candidates (deps done/updated, not running/error), purges duplicates.
- Applies resource requests from `rules[workflow][task]["resources"]`; tracks requested vs available; delays jobs exceeding limits.
- Runs jobs (spawn via `job.fork`) with per-job Log severity (`rules.defaults.log` or overrides).
- Handles recoverable errors (non-ScoutException): retries once after clean; logs and continues non-recoverable or repeated failures.
- Erases dependency artifacts when rules specify `erase: true` for the dep task and top-level jobs are unaffected; archives dep info to parent (see tests).
- Workflow helpers:
  - `Workflow.produce(jobs, produce_cpus:, produce_timer:)` — run one or more jobs under Orchestrator.
  - `Workflow.produce_dependencies(jobs, tasks, produce_cpus:, produce_timer:)` — pre-produce specific dependency tasks for given jobs.

---

## Task aliases and overrides

Create a task that aliases another task's output:

```ruby
task_alias :say_hello, self, :say, name: "Miguel"
# alias name => inferred type, returns and extension from :say
```

Behavior:
- The alias depends on the original task; upon completion:
  - With config forget/remove enabled (see below), the alias job archives dependency info and either hard-links, copies, or removes dep artifacts.
  - Otherwise links dep files_dir and result file directly (or copies for remote steps).
- Control via config or environment:
  - SCOUT_FORGET_TASK_ALIAS / SCOUT_FORGET_DEP_TASKS (true) to forget deps on alias (also RBBT_ variants).
  - SCOUT_REMOVE_TASK_ALIAS / SCOUT_REMOVE_DEP_TASKS (= 'true' or 'recursive') to remove dep files.
- The alias keeps the dep extension (`extension :dep_task` when not set).
- Mark alias as not overridden by inputs via option `:not_overriden => true`.

Overriding dependencies at job time:
- Pass `"Workflow#task" => Step_or_Path` in job inputs; the system marks dep as overridden, adjusts naming, and uses provided artifact.

---

## Usage and documentation

Workflow usage:
- Set `self.title`, `self.description` on the workflow.
- Provide per-task descriptions via `desc "..."` immediately before task.
- If the workflow repo includes `workflow.md` or `README.md`, it is parsed to fill title/description and to attach extended descriptions to tasks (via parse_workflow_doc).

Programmatic usage:
- `workflow.usage` — prints a summary of tasks and their short descriptions plus abridged dependency sequences.
- `workflow.usage(task)` — detailed task usage:
  - Shows inputs (types, defaults) and their CLI flags (from SOPT metadata).
  - Lists inherited inputs from dependencies (those not fixed by dep options).
  - Explains list/file conventions for array/file inputs.
  - Shows Returns type and an abridged dependency graph.

Task usage:
- `task.usage(workflow)` — render usage of a single task (See Usage tests).

SOPT integration:
- For CLI, a task generates option descriptors from recursive inputs:
  - `task.get_SOPT` returns parsed `--input` options from ARGV.
  - Boolean inputs render as `--flag`; string-like inputs accept `--key=value` or `--key value`.
  - Array inputs accept comma-separated values; file/path arrays resolve files.

---

## Entity workflows

EntityWorkflow extends Workflow with an entity pattern, where tasks operate on one or many “entities” (strings or annotated objects):

```ruby
module People
  extend EntityWorkflow
  self.name = 'People'
  self.entity_name = 'person'  # default: 'entity'

  property :introduction do
    "My name is #{self}"
  end

  entity_task hi: :string do
    "Hi. #{entity.introduction}"
  end

  list_task group_hi: :string do
    "Here is the group: " + entity_list.hi * "; "
  end
end

People.setup("Miki").hi           # => "Hi. My name is Miki"
People.setup(%w[Miki Clei]).group_hi
```

- entity_task / list_task / multiple_task define tasks and matching convenience properties.
- For properties, call `.property task_name => property_type` to define accessors that trigger jobs and return run values.
- `annotation_input(name, type, desc, default, options)` declares entity annotation-sourced inputs; automatically wired as inputs for property tasks.

---

## Persist helper

Inside Workflow modules:
- `persist(name, type = :serializer, options = {}, &block)` — thin wrapper around Persist.persist with default dir under `Scout.var.workflows[workflow.name].persist`.

---

## Path integration (step files)

`Path.step_file?(path)` identifies paths under `.files` for step artifacts and generates a compact digest string. Path#digest_str is overridden to render step file info: "Step file: <Workflow>/<task>/<...>.files/...".

---

## Queue helpers

The queue subsystem lets you enqueue jobs (inputs saved on disk) and process them:

- `Workflow.queue_job(file)` — build a job from a queue file path `.../<workflow>/<task>/<name>...`:
  - If the path is a directory or a non-empty file, parses inputs via Task.load_inputs.
  - Infers clean job name (jobname input) from file base if present.
- `Workflow.unqueue(file)` — lock, run job, and remove queue file.
- CLI `scout workflow process` processes queue entries continuously or once (see below).

---

## API quick reference

Workflow (module-level and instance):
- Workflow.annonymous_workflow(name=nil) { ... } => Module (extends Workflow)
- Workflow.require_workflow(name) => Module (loads from workflows/<name>/workflow.rb or autoinstalls)
- Workflow.install_workflow(name[, base_repo_url]) and update_workflow_dir
- workflow.name / directory / directory= — job storage
- helper(:name) { ... } and helper(:name, args...) to call
- input(name, type, desc=nil, default=nil, options={})
- dep(workflow, task, options={}, &block) | dep(task, options={}, &block)
- desc, returns, extension
- task(name => type, &block)
- task_alias(name, workflow, original_task, options={}, &block) — alias dep_task
- job(task_name, jobname=nil, provided_inputs={}) => Step
- find_in_dependencies(name, dependencies) — find dep with name
- Documentation:
  - title, description, documentation (parse_workflow_doc)
  - usage([task], abridge=false)
  - task_info(task_name) => hash of inputs, defaults, returns, deps, extension
- Orchestration:
  - Workflow.produce(jobs, produce_cpus:, produce_timer:)
  - Workflow.produce_dependencies(jobs, tasks, produce_cpus:, produce_timer:)
- Persist: persist(name, type, options) { ... }

Task:
- Task.setup(&block) — create a task proc with annotation attributes
- annotation attrs: name, type, inputs, deps, directory, description, returns, extension, workflow
- inputs — array of [name, type, desc, default, options]
- job(id=nil, provided_inputs=nil) => Step
- exec_on(binding, *inputs) — eval block on a binding (obj) with inputs
- assign_inputs(provided_inputs, id=nil) => [input_array, non_default_inputs, jobname_input?]
- process_inputs(provided_inputs, id=nil) => [input_array, non_default_inputs, digest_str]
- dependencies(id, provided_inputs, non_default_inputs, compute) => [Step...]
- recursive_inputs(overridden=[]) => inputs array
- save_inputs(dir, provided_inputs) and load_inputs(dir)

Step:
- run(stream = false | :no_load | :stream), exec, join, stream, consume_all_streams
- status: done?, error?, aborted?, running?, waiting?, updated?, dirty?, started?, recoverable_error?
- info (load_info, save_info, set_info, merge_info), info_file, messages, log
- paths: path, tmp_path, files_dir, file, files, bundle_files
- deps: dependencies, input_dependencies, rec_dependencies(connected=false), all_dependencies
- provenance: Step.prov_report(step, ...)
- resolving/relocating: Step.load(path), Step.relocate(path)
- concurrency: child { ... }, cmd(...), progress_bar, traverse
- cleaning: clean, recursive_clean, produce(with_fork: false), grace, terminated?
- overriden?: overriden_task, overriden_workflow, overriden_deps, recursive_overriden_deps
- digest_str, fingerprint, short_path, task_signature, alias?, step(:task_name)

Orchestrator:
- Orchestrator.new(timer=5, available_resources={cpus: Etc.nprocessors})
- process(rules, jobs), candidates, job_workload, workload, job_rules, job_resources
- release_resources, check_resources (internal)

---

## Command Line Interface (scout workflow)

The scout command discovers and runs scripts under scout_commands using the Path subsystem. For Workflow:

- General dispatcher:
  - scout workflow cmd <workflow> [<subcommand> ...]
    - Navigates <workflow>/share/scout_commands/<subcommand> (nested).
    - If a directory is selected, lists available subcommands.
    - If a file is found, it is executed; remaining ARGV parsed with SOPT.

- List installed workflows:
  - scout workflow list

- Install or update workflows:
  - scout workflow install <WorkflowName> [<repo_base_url>]
    - workflow can be 'all' to update all installed workflows.
    - Autoinstall on demand is enabled by SCOUT_WORKFLOW_AUTOINSTALL=true.
    - Defaults repo base to 'https://github.com/Scout-Workflows/' (or config).

- Run a workflow task:
  - scout workflow task <workflow> <task> [--jobname NAME] [--deploy serial|local|queue|SLURM|<server>|<server-slurm>] [--fork] [--nostream] [--update] [--load_inputs DIR|TAR] [--save_inputs DIR|TAR] [--printpath] [--provenance] [--clean] [--recursive_clean] [--clean_task task[,task2,...]] [--override_deps Workflow#task=path[,...]] [task-input-options...]
    - Input options are auto-generated from task recursive inputs (e.g. --name, --count, etc.).
    - --nostream disables streaming (writes file then prints content).
    - --update recomputes if deps are newer.
    - --deploy:
      - serial — run in current process and stream output.
      - local — run with local Orchestrator (uses cpus = Misc.processors).
      - queue — save inputs to queue dir and exit.
      - SLURM — submit via SLURM (requires rbbt-scout/hpc).
      - <server> or <server-slurm> — offsite execution helpers (if configured).
    - --fork — fork and return the job path immediately.
    - --load_inputs — load inputs from a directory or tar.gz bundle (see save_inputs).
    - --save_inputs — save current inputs to directory or tar.gz bundle and exit.
    - --printpath — print step path after completion.
    - --provenance — print provenance report and exit.
    - --clean, --recursive_clean — cleanup artifacts.
    - --clean_task — clean matching dependency tasks (optionally qualified as Workflow#task).
    - --override_deps — override specific dependencies with paths.

  Examples:
  - scout workflow task Baking bake_muffin_tray --add_bluberries
  - scout workflow task UsageWorkflow step2 --array "a,b" --float 1.5
  - scout workflow task MyWF my_task --override_deps "MyWF#dep1=/path/result1,OtherWF#depX=/path/resultX"

- Job info:
  - scout workflow info <step_path> [-i|--inputs | -ri|--recursive_inputs]
    - Without flags prints the job info hash (status, pid, times, messages, inputs, dependencies).
    - --inputs prints input_names and inputs.
    - --recursive_inputs prints all inputs (including propagated).

- Provenance:
  - scout workflow prov <step_path> [-p|--plot file.png] [-i inputs,csv] [--info_fields fields,csv] [-t|--touch] [-e|--expand_repeats]
    - Prints a colorized dependency tree or plots a graph (requires R/igraph).
    - --touch updates mtimes of parents consistent with deps.

- Execution trace:
  - scout workflow trace <job-result> [options]
    - Options: --fix_gap, --report_keys key1,key2,..., --plot file.png, --width N, --height N, --size N, --plot_data
    - Prints a per-task summary by default (calls, avg time, total time).
    - With --plot_data prints a per-step table with start/end offsets since first start.
    - Accepts multiple jobs; includes archived info when available.

- Queue processing:
  - scout workflow process [<workflow> [<task> [<name>]] | <queue_file>] [--list] [--continuous] [--produce_timer N] [--produce_cpus N] [-r|--requires file1,file2]
    - Without args, processes all queued jobs under var/queue.
    - --list lists matched queue files and exits.
    - --continuous loops and re-checks for new jobs.
    - --requires auto-requires Ruby files before processing.
    - Produces jobs via Orchestrator with given cpus/timer.

- Write info:
  - scout workflow write_info <job-result> <key> <value> [--force] [--recursive] [--check_pid]
    - Sets an info key/value for a job and optionally all deps (and archived deps), respecting pid/host filters if requested.
    - Use value 'DELETE' or 'nil' to remove a key (forces).

CLI discovery:
- All workflow CLI scripts live under <workflow>/share/scout_commands/workflow/*.
- The dispatcher `scout workflow cmd` allows invoking any custom scripts shipped with a workflow package.
- If you specify a directory rather than a script, the CLI lists available subcommands.

---

## Examples

Define a workflow with inputs, deps, and tasks:

```ruby
module Pantry
  extend Resource
  self.subdir = 'share/pantry'

  claim Pantry.eggs, :proc { "Eggs" }
  claim Pantry.flour, :proc { "Flour" }
  claim Pantry.blueberries, :proc { "Blueberries" }
end

module Baking
  extend Workflow
  self.name = "Baking"

  helper(:whisk) { |eggs| "Whisking eggs from #{eggs}" }
  helper(:mix)   { |base, mixer| "Mixing base (#{base}) with mixer (#{mixer})" }
  helper(:bake)  { |batter| "Baking batter (#{batter})" }

  task :whisk_eggs => :string do
    whisk(Pantry.eggs.produce)
  end

  dep :whisk_eggs
  input :add_bluberries, :boolean
  task :prepare_batter => :string do |add_bluberries|
    whisked = step(:whisk_eggs).load
    batter  = mix(whisked, Pantry.flour.produce)
    batter  = mix(batter, Pantry.blueberries.produce) if add_bluberries
    batter
  end

  dep :prepare_batter
  task :bake_muffin_tray => :string do 
    bake(step(:prepare_batter).load)
  end
end

# Run
Baking.directory = Path.setup("tmp/var/jobs/baking")
Baking.job(:bake_muffin_tray, "Blueberry muffin", add_bluberries: true).run
# => "Baking batter (Mixing base (Mixing base (Whisking eggs from share/pantry/eggs) with mixer (share/pantry/flour)) with mixer (share/pantry/blueberries))"
```

Streaming dependent steps:

```ruby
times = 1000
producer = wf.task(:producer => :array) do |n|
  Open.open_pipe do |sin|
    n.times { |i| sin.puts "line-#{i}" }
  end
end

consumer = wf.task(:consumer => :array) do
  p = dependencies.first
  stream = p.stream
  Open.open_pipe do |sin|
    while line = stream.gets
      sin.puts line if line.split("-").last.to_i.even?
    end
  end
end

s1 = producer.job(nil, n: times)
s2 = consumer.job(nil, inputs: {}) # using dep
s2.dependencies = [s1]

io = s2.run(true)
lines = io.read.split("\n")
io.join
# lines.length == times/2
```

Orchestrate with resource rules:

```ruby
jobs = 6.times.map { |i| Baking.job(:bake_muffin_tray, "Job #{i}") }
rules = { "defaults" => { "log" => 4 }, "default_resources" => { "IO" => 1 }, "Baking" => { "bake_muffin_tray" => { "resources" => { "cpus" => 4 } } } }
Workflow::Orchestrator.new(0.1, "cpus" => 8, "IO" => 4).process(rules, jobs)
```

Task aliases and cleanup:

```ruby
module Greeter
  extend Workflow
  self.name = "Greeter"

  input :name, :string, jobname: true
  task :say => :string do |name| "Hi #{name}" end

  task_alias :say_miguel, self, :say, name: "Miguel"
end

Greeter.job(:say_miguel).run # => "Hi Miguel"
```

Provenance:

```ruby
job = Baking.job(:bake_muffin_tray, "Normal", add_bluberries: false).run
puts Step.prov_report(job)
# or via CLI:
# scout workflow prov var/jobs/Baking/bake_muffin_tray/<id>
```

---

This document covers the Workflow engine: defining tasks and dependencies, creating and running jobs, streaming, info management, orchestration, documentation, and CLI integration. Use it to build reproducible pipelines with safe persistence and rich provenance.