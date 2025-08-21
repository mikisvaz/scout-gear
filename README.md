# Scout Gear

Scout Gear is the core, higher-level module set of the Scout framework. It bundles rich, production-grade data and workflow tooling built on top of the lower-level primitives in scout-essentials, and adds domain abstractions such as TSV processing, workflows, knowledge bases, entity typing, parallel work queues, and more.

Layering:
- scout-essentials: foundational utilities used everywhere (Path, Open, CMD, IndiferentHash, Persist, Resource, etc.)
- scout-gear (this repo): TSV, Workflow, KnowledgeBase, Entity/Association, WorkQueue, Semaphore, and glue code
- Additional packages:
  - scout-camp: remote servers, cloud deployments, web interfaces, cross-site operations
  - scout-ai: model training and chat agents
  - scout-rig: connect with other languages (e.g., Python)

Related ecosystem:
- Rbbt (Ruby bioinformatics): Many of Scout’s ideas and utilities originated in Rbbt. It still provides a broad set of bioinformatics workflows and tools. See the Rbbt-Workflows organization for many real-world examples and usage patterns:
  - https://github.com/Rbbt-Workflows

For module-specific guides, see doc/*.md in this repository (linked below).

- TSV: doc/TSV.md
- Workflow: doc/Workflow.md
- KnowledgeBase: doc/KnowledgeBase.md
- Association: doc/Association.md
- Entity: doc/Entity.md
- WorkQueue: doc/WorkQueue.md
- Semaphore: doc/Semaphore.md

Additionally, Scout Gear reuses and exposes core facilities from scout-essentials. Summaries of those core modules are included below for convenience.

---

## How command-line interfaces work (scout …)

Scout provides a single “scout” command that discovers and runs nested subcommands from any installed Scout package. Scripts are discovered using the Path subsystem across PATH-like roots, enabling workflows or packages to inject their own commands.

Basics:
- The CLI resolves terms left-to-right until a file is found under a scout_commands tree.
  - Example: scout workflow task runs scout_commands/workflow/task
  - Example: all TSV-related scripts are under scout_commands/tsv and can be listed with scout tsv
- If the path resolves to a directory instead of a script, a list of available subcommands in that directory is shown.
- Remaining ARGV is parsed by the selected script using SimpleOPT (SOPT) or compatible parsers.
- Because discovery uses Path maps, commands contributed by other packages or installed workflows are automatically found.

See the per-module CLI sections below for TSV, Workflow, and KnowledgeBase.

---

## Scout Essentials: Core building blocks

Scout Gear depends on the following main modules from scout-essentials. You’ll use these directly for filesystem/resource orchestration, external command execution, caching, and options handling.

### Path

doc/Path.md

Path is a lightweight, annotation-enabled “smart string” for composing and locating project resources across multiple search maps (current/user/global/lib/tmp, etc.). It integrates with Open and Persist.

Highlights:
- Path.setup("str") turns a String into a Path with join via [], /, or method_missing (path.foo.bar)
- Map logical locations to physical roots with path maps; find the first match across map order with path.find (and path.find_all)
- Filename helpers: get/set/replace/unset extensions; sanitize filenames; relative paths
- Directory helpers: glob and glob_all over maps; dirname/basename; realpath; newer?
- Digest summaries: path.digest_str summarizes files/dirs for logging/debugging

Usage:
```ruby
p = Path.setup('share/data/myfile')
p.find             # resolve across configured maps
p[:subdir, :file]  # joins => share/data/subdir/file
```

### Open

doc/Open.md

Open unifies file/stream/remote I/O, atomic writes, pipes/tees/FIFOs, (bg)zip helpers, rsync/sync, and lock handling.

Highlights:
- Open.open/read/write with auto-(de)compression for .gz/.bgz/.zip and remote urls (wget/ssh)
- Streams: open_pipe, tee_stream, consume_stream, with_fifo
- Safe writes: sensible_write (tmp + atomic rename + optional locks)
- Remote: wget with caching, ssh/scp, digest_url, remote cache
- Filesystem: mkdir/mkfiledir, mv/cp/ln/link_dir, rm/rm_rf, same_file?, exists?, writable?
- Locking: Open.lock wraps a robust Lockfile (NFS-safe) with refresh/timeout/steal

Example:
```ruby
Open.sensible_write("out.txt", Open.open("http://example.com"))
Open.with_fifo { |fifo| ... }
Open.rsync("src/", "user@server:dst/", delete: true)
```

### CMD

doc/CMD.md

CMD wraps Open3.popen3 with robust patterns for streaming, stderr logging, stdin feeding, auto-join of producers, and tool discovery/installation.

Highlights:
- CMD.cmd("tool args", pipe: true, in: io_or_string, stderr: Log::HIGH, autojoin: true)
- ConcurrentStream-enabled stdout with join/error propagation
- Convenience: CMD.bash("bash -l -c '...'"), cmd_pid/cmd_log
- Tool registry: CMD.tool, CMD.get_tool (auto-install via conda or producers), version scanning

Example:
```ruby
io = CMD.cmd("cut", "-f" => 2, "-d" => " ", in: "a b", pipe: true)
io.read # => "b\n"; io.join
```

### IndiferentHash

doc/IndiferentHash.md

Hash mixin for indifferent access (string/symbol keys equal), deep-merge, options parsing, and string<->hash conversions.

Highlights:
- IndiferentHash.setup(hash) to extend a single hash instance
- Access with h[:a] == h["a"]; delete/include? are indifferent
- Helpers: deep_merge, values_at with indifferent keys, slice, except
- Options utilities: parse_options, process_options, positional2hash, hash2string/string2hash

Example:
```ruby
opts = IndiferentHash.parse_options('limit=10 title="A title"')
opts[:title] # => "A title"
```

### Persist (core serialization/caching)

doc/Persist.md (essentials)

Typed serialization (json/yaml/marshal/binary/arrays), atomic saves, and the high-level persist pattern with locking and streaming.

Highlights:
- Persist.save/load(obj, file, type)
- Persist.persist(name, type, dir: ...) { compute_or_stream }
  - Locking and tmp-to-final atomic writes
  - Streaming tee: one copy to file, one to caller
- Memory cache: Persist.memory(name) { ... }
- Helpers to parse YAML/JSON/Marshal via Open

Example:
```ruby
val = Persist.persist("expensive", :json) { compute_hash }
# subsequent calls load cached JSON unless :update or stale
```

### Resource

doc/Resource.md

Resource system to claim and produce files on demand (string/proc/url/rake/installers), integrated with Path/Open and locking.

Highlights:
- claim path => (:string, :proc, :url, :rake, :install)
- Produce on demand via path.produce and path.open/read
- Rake integration: drive file tasks/rules to generate outputs
- Install software into a per-resource “software” dir and update env

Example:
```ruby
module MyPkg
  extend Resource
  claim root.tmp.test.hello, :string, "Hello"
end
MyPkg.tmp.test.hello.read # produces if missing, then reads
```

Other essentials you’ll encounter:
- Annotation / AnnotatedArray / NamedArray: lightweight typed attributes on objects and arrays; named tuple-style rows
- ConcurrentStream: concurrency-aware streams with join/abort/callbacks
- SimpleOPT (SOPT): tiny CLI option DSL/parser; used by scout commands
- Log: leveled, colored logging; progress bars; fingerprint utilities
- TmpFile: temp files/dirs and stable tmp path generator for caches

---

## Scout Gear modules

Scout Gear builds on essentials to deliver domain abstractions and engines.

### TSV

doc/TSV.md

A flexible, typed table abstraction with robust parser, streaming dumper/transformer, parallel traversal, joins/attachments, identifier translation, on-disk persistence (TokyoCabinet/Tkrzw), and range/position indices.

Highlights:
- Shapes: :double, :list, :flat, :single; key_field + fields
- Parse TSV/CSV from files/streams/strings with rich header options (sep, type, cast, merge)
- Dumper/Transformer for streaming pipelines
- TSV.traverse(obj, cpus: N, into: …) for parallel iteration
- Attach, change_key, change_id, translate via identifier indices
- Persistence via TSVAdapter over HDB/BDB/Tkrzw/FWT/PKI/Sharder
- Streaming paste/concat/collapse utilities; filters with persisted sets

Example:
```ruby
tsv = TSV.open(path, persist: true, type: :double)
tsv.attach(other, complete: true)
index = TSV.index(tsv, target: "FieldA")
```

CLI (scout tsv):
- Scripts live under scout_commands/tsv; list with scout tsv
- Run a specific subcommand: scout tsv <subcommand> [options] [args...]
- If you hit a directory, available subcommands are listed
- Subcommands parse options with SOPT (see each script’s help)

### Workflow

doc/Workflow.md

A lightweight workflow engine. Define tasks with typed inputs and dependencies, create jobs (Steps), and run them with persistence, streaming, provenance, and orchestration under resource rules.

Highlights:
- input/dep/task DSL with helper methods; task_alias and overrides
- Jobs (Step): run/load/stream/join, info files, files_dir, provenance
- Orchestrator: schedule dependent jobs under cpus/IO constraints; retry recoverable errors; archive/erase deps per rules
- EntityWorkflow: entity-centric tasks and properties
- Queue helpers to enqueue and process jobs

Example:
```ruby
module Baking
  extend Workflow
  task :say => :string do |name| "Hi #{name}" end
end

Baking.job(:say, "Miguel").run # => "Hi Miguel"
```

CLI (scout workflow):
- List workflows: scout workflow list
- Run a task: scout workflow task <workflow> <task> [--jobname NAME] [input options...]
  - Options include --fork, --nostream, --update, --printpath, --provenance, --clean, --recursive_clean, --override_deps, --deploy (serial|local|queue|SLURM|server)
- Show job info: scout workflow info <step_path> [--inputs|--recursive_inputs]
- Provenance: scout workflow prov <step_path> [--plot file.png] […]
- Trace execution: scout workflow trace <job-result> [options]
- Process queue: scout workflow process [filters] [--continuous] [--produce_cpus N] […]

You can also dispatch workflow-specific custom commands via:
- scout workflow cmd <workflow> <subcommand> … (discovers scripts under <workflow>/share/scout_commands/workflow)

### KnowledgeBase

doc/KnowledgeBase.md

A thin orchestrator around Association, TSV, Entity, and Persist to register multiple association databases, normalize/index them, query/traverse across them, manage entity lists, and generate markdown descriptions.

Highlights:
- Register databases with source/target specs and identifier files
- get_database/get_index (BDB-backed) with undirected options
- Query: all, subset (children/parents/neighbours), identify/translate entities
- Lists: save/load/delete/enumerate typed lists
- Traversal DSL: multi-hop path finding with wildcards/conditions
- Markdown descriptions from registry/README files

Example:
```ruby
kb = KnowledgeBase.new(Path.setup("var/kb"), "Hsa")
kb.register :brothers, datafile_test(:person).brothers, undirected: true
kb.children(:brothers, "Miki") # => ["Miki~Isa", ...]
```

CLI (scout kb):
- Configure KB: scout kb config [options] <name>
- Register DB: scout kb register [options] <name> <filename>
- Declare entities: scout kb entities <entity> <identifier_files>
- Show info: scout kb show [<name>]
- Query: scout kb query <name> <entity_spec>
- Lists: scout kb list [<list_name>]
- Traverse: scout kb traverse [options] "<rules,comma,separated>"

### Association

doc/Association.md

Utilities to normalize source/target field specifications from TSVs, open normalized association databases with optional identifier translation, and build pairwise “source~target” indices (optionally undirected). Also includes AssociationItem for entity-like behavior over pair strings and utilities to build incidence/adjacency matrices.

Example:
```ruby
idx = Association.index(file, source: "=>Name", target: "Parent=>Name", undirected: true)
idx.match("Clei")       # => ["Clei~Guille"]
idx.to_matrix           # boolean incidence matrix
```

### Entity

doc/Entity.md

Annotate plain values or arrays as entities with behavior-rich “properties”, automatic format mapping, identifier translation (Entity::Identified), array-aware property batching/caching, and persistence for property results via Persist.

Example:
```ruby
module Person
  extend Entity
  property :greet => :single do "Hi #{self}" end
end
Person.setup("Miki").greet
```

### WorkQueue

doc/WorkQueue.md

A multi-process work pipeline (forked workers + semaphore-guarded sockets) to parallelize processing over a stream of inputs, with robust error propagation.

Example:
```ruby
q = WorkQueue.new(4){|x| x * 2}
out = []; q.process{|y| out << y}
(1..100).each{|i| q.write i}; q.close; q.join
```

### Semaphore (ScoutSemaphore)

doc/Semaphore.md

Concurrency helpers based on POSIX named semaphores (via RubyInline C bindings), plus higher-level helpers to bound concurrency with forks/threads.

Example:
```ruby
ScoutSemaphore.with_semaphore(2) do |sem|
  ScoutSemaphore.synchronize(sem){ critical_work }
end
```

---

## Examples and further reading

- This repository’s docs directory provides in-depth guides for each module:
  - TSV: doc/TSV.md
  - Workflow: doc/Workflow.md
  - KnowledgeBase: doc/KnowledgeBase.md
  - Association: doc/Association.md
  - Entity: doc/Entity.md
  - WorkQueue: doc/WorkQueue.md
  - Semaphore: doc/Semaphore.md
- For numerous end-to-end examples and real datasets, explore the Rbbt-Workflows organization:
  - https://github.com/Rbbt-Workflows
- For foundational utilities (Path, Open, CMD, IndiferentHash, Persist, Resource, etc.), consult the scout-essentials documentation:
  - Those modules are summarized above and used pervasively across Scout Gear.

---

## Notes

- Streaming everywhere: many APIs return ConcurrentStream-enabled IOs. Always read to EOF and join (or rely on autojoin) to ensure producers exit and errors are surfaced.
- Atomicity and locking: Open.sensible_write and Persist.persist use tmp+mv and lockfiles to provide robust cross-process behavior.
- Discovery and composition: the Path subsystem and Resource claims make it easy to build portable projects with on-demand production of resources and discoverable commands.