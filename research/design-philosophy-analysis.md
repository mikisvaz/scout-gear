Truncated (9723): # Investigation: Design Philosophy and Coding Conventions

> **Non-normative.** This document is a working investigation with
> implementation details, code exploration notes, and hypotheses. Refer to
> `doc/developer/` for maintained architectural documentation.

## Overview

scout-gear shares the design philosophy of scout-essentials. This document
analyzes the gear-specific patterns, abstractions, and coding conventions
that make the codebase distinctive.

The four foundational principles (shared with scout-essentials):

1. **Annotation-based extensibility** — Objects carry their own metadata.
2. **Streaming-first architecture** — Data flows through pipes wherever possible.
3. **Persistence-as-caching** — Every expensive computation can be cached.
4. **Convention-over-configuration** — Paths and identifiers are derived, not configured.

scout-gear adds:

5. **The Annotation object** — Not just data; the annotation IS the object type.
6. **The `into:` pattern** — Streaming operations are composable.
7. **The `Persist.tsv` adapter pattern** — Multiple database engines behind a uniform interface.
8. **Lazy dependency resolution** — Dependencies resolve at job creation time, not definition time.

## Pillar 1: Annotation-based extensibility

### The "annotated object" pattern

In scout-gear, annotations are not optional metadata — they define object
identity. A String becomes a `Gene` by being annotated. A Hash becomes a
`TSV` by being set up. A block becomes a `Task` by being annotated.

This means the type system is dynamic and composable:

```ruby
# A plain String
gene_id = "ENSG00000141510"

# Annotated as a Gene
Gene.setup(gene_id)
gene_id.length  # Now calls the Gene#length property

# A Hash becomes a TSV
tsv = {"a" => ["1", "2"]}
TSV.setup(tsv, :key_field => "Gene", :fields => ["Value"])
tsv.to_list  # Now has TSV methods
```

**Philosophy**: Don't create new classes for every data type. Instead,
extend existing objects with the behaviors they need. This avoids
hierarchical inheritance and keeps objects flexible.

### The `Annotation` module

`Annotation` (from scout-essentials) is the foundation. It provides:

- `extend Annotation` — Make a module able to annotate objects
- `setup(obj, *args)` — Annotate an object with this module's behavior
- `annotation :foo, :bar` — Declare persistent annotation attributes

All major scout-gear objects use this:
- `Workflow` (annotation: name, tasks, helpers)
- `Task` (annotation: name, type, inputs, deps, description)
- `Step` (annotation: path, inputs, dependencies)
- `TSV` (annotation: type, key_field, fields, namespace)
- `Entity` (annotation: format, options)

See the scout-essentials documentation on the Annotation system for details:
[Annotation System](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/AnnotationSystem.md)

## Pillar 2: Streaming-first architecture

### The `ConcurrentStream` protocol

scout-gear builds on the `ConcurrentStream` protocol from scout-essentials,
which adds callback-based completion to IO streams. The key extension in
scout-gear is the **Transformer** pattern.

See:
[Handling Streams](https://github.com/mikisvaz/scout-essentials/blob/main/doc/user/HandlingStreams.md)
[Streaming Model](https://github.com/mikisvaz/), the `into:` pattern lets you chain streaming operations without manual thread/sync management:

```ruby
tsv = TSV.open("data.tsv")
transformer = tsv.traverse(:key, :into => :tsv) do |k, v|
  [k, v.collect { |x| x * 2 }]
end
```

Here `traverse` with `into: :tsv` produces a new TSV by streaming each row
through the block. The `into:` target can be `:tsv`, `:dumper`, or any
object that responds to `<<`.

### The Transformer abstraction

`TSV::Transformer` wraps a source TSV and a processing block, producing a
streaming output. It's used in:

- `TSV#attach` — Join two TSVs (streaming join)
- `TSV#select` / `TSV#reject` — Filter rows
- `TSV#reorder` / `TSV#slice` — Restructure
- `Association.index` — Build association indexes
- `TSV#change_id` — Translate identifiers

The Transformer is deadlock-safe because it always uses a single thread for
reading and a single thread for writing, connected by a pipe.

## Pillar  abstraction: Persistence-as-caching

### The `Persist.persist` pattern

Every expensive operation is wrapped in `Persist.persist`, which provides:
- **Caching**: Result is stored on disk under a deterministic path
- **Locking**: File locks prevent duplicate computation
- **Atomicity**: Results are written to a temp file then moved atomically

```ruby
result = Persist.persist("MyApp/heavy_compute", :tsv) do |filename|
  heavy_computation  # Only runs if not already cached
end
```

In scout-gear, this is extended with:

### `Persist.tsv`

`Persist.tsv` is the TSV-aware version. It opens a database (TokyoCabinet
HDB by default), mixes in the TSVAdapter module, and lets you populate it:

```ruby
tsv = Persist.tsv("MyApp/index", :engine => :HDB) do |data|
  data["key"] = ["value"]
end
```

The resulting `data` is both a TokyoCabinet HDB (database operations) and a
TSV (annotation operations). The TSVAdapter handles serialization and
annotation persistence transparently.

## Pillar 4: Convention-over-configuration

### Path derivation

scout-gear derives paths from content, not configuration:

```
var/jobs/<Workflow>/<task>/<digest>.<ext>
```

The digest is computed from inputs and dependencies. If inputs change, the
path changes — you always know where results are stored without explicit
configuration.

### Identifier derivation

Entity formats, identifier translation files, and namespace files all
follow predictable path conventions:

```
var/<namespace>/identifiers/<format>%to<format>
var/<namespace>/mappings/<type>
```

## Pillar 5: Lazy dependency resolution

### The `dep` pattern

Dependencies are declared at task-definition time but resolved at
job-creation time. This allows:

```ruby
dep :task_a
dep :task_b
task :task_c => :tsv do |taska, taskb|
  # taska and taskb are Step objects
  taska.path + " + " + taskb.path
end
```

The `dep` calls queue up annotations. At `task` definition time, they are
consumed and attached to the Task. At `job` creation time, they are
resolved into Step objects.

**Dynamic dependencies** are supported via blocks:

```ruby
dep do |jobinput, inputs|
  if inputs[:option]
    [AnotherWorkflow.job(:some_task, input)]
  else
    []
  end
end
```

The block receives the job's inputs and can return:
- A Step object
- A Hash with `:workflow`, `:task`, `:inputs`
- An Array of either

## Pillar 6: The TSVAdapter pattern

### Multiple engines, one interface

The TSVAdapter pattern lets any database engine behave like a TSV:

```
Persist.tsv
    ↓ (selects engine)
TokyoCabinet HDB  ←  TSVAdapter  →  behaves like a TSV
FixWidthTable     ←  TSVAdapter  →  behaves like a TSV
PackedIndex       ←  TSVAdapter  →  [not fully TSV-compatible, positional access]
Sharder           ←  TSV.TSVAdapter  →  behaves like a TSV
```

The adapter handles:
- Annotation persistence (metadata stored alongside data)
- Serialization (type-aware encoding of values)
- Locking (read/write locks via file locks)
- TSV method forwarding (keys, each, [], []=, etc.)

## Idiomatic vs non-idiomatic code

### Idiomatic: Use annotations to extend behavior

```ruby
# GOOD: Annotate an existing object
Gene.setup(gene_id)
gene_id.length

# BAD: Create a new class hierarchy
class GeneID
  def initialize(id); @id = id; end
  def length; ...; end
end
```

### Idiomatic: Stream data through operations

```ruby
# GOOD: Streaming pipeline with `into:`
tsv.traverse(:key, :into => :tsv) { |k, v| [k, transform(v)] }

# BAD: Load everything into memory, process, write
data = tsv.to_hash
new_data = data.transform_values { |v| transform(v) }
TSV.new(new_data)
  # then write
```

## Cross-references to scout-philosophy

The design principles documented here are consistent with and build upon:
- [Annotation System](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/AnnotationSystem.md)
- [Design Principles](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/DesignPrinciples.md)
- [Streaming Model](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/StreamingModel.md)
- [Caching Results](https://github.com/mikisvaz/scout-essentials/blob/main/doc/user/CachingResults.md)
