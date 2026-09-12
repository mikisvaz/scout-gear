# Design Principles

This document describes the coding conventions and design philosophy of
scout-gear. It is intended for framework contributors who want to write
code that fits naturally into the codebase.

For the foundational principles shared with scout-essentials, see
[scout-essentials: Design Principles](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/DesignPrinciples.md).

## Core philosophy

Scout-gear follows three principles:

1. **Annotate, don't subclass** — Attach behavior to existing objects
   rather than creating new classes.
2. **Stream, don't load** — Process data row-by-row through pipes instead
   of materializing it in memory.
3. **Persist as cache** — Every expensive computation should be
   transparently cached and recomputed only when inputs change.

## Annotate, don't subclass

The TSV is a plain Ruby Hash. It's not a subclass of Hash — it *is* a
Hash, with annotations attached. The annotations carry metadata (key
field, fields, type, namespace) and methods (traverse, attach, index).

```ruby
# Idiomatic: annotate a Hash
data = {"gene1" => ["100"]}
TSV.setup(data, type: :list, key_field: "Gene", fields: ["Expr"])
# data is still a Hash, but now has TSV methods

# Non-idiomatic: create a TSV subclass
class MyTSV < Hash  # WRONG
  def initialize
    @type = :list
  end
end
```

Similarly, an Entity is a plain String with annotations. A Step is a
String path with annotations. A Task is a Module with annotations
(`Workflow` modules extend `Annotation`, `workflow/definition.rb:12`).

**Why?** Because annotation preserves duck-typing. A TSV can be passed to
any function that expects a Hash. An Entity can be passed to any function
that expects a String. Subclassing breaks this.

## Stream, don't load

When processing large datasets, never load the entire dataset into memory.
Instead, use the traverse API to process rows one at a time, streaming
results through pipes.

```ruby
# Idiomatic: streaming transform (class method, supports cpus:/into:)
result = TSV.traverse(tsv, into: {}) do |key, values|
  [key, transform(values)]
end

# Non-idiomatic: load everything, then transform
new_hash = {}
tsv.each do |key, values|          # materializes everything
  new_hash[key] = transform(values)
end
```

Note the distinction: the **instance** method `tsv.traverse(:key,
into: :tsv)` has no `cpus:` parameter; parallel streaming is the
**class** method `TSV.traverse(obj, cpus: N, into: target)`
(`tsv/open.rb:36`). See [TSV Internals](TSVInternals.md).

The traverse API uses a Dumper/Transformer pair that writes to a pipe in
one thread and reads from it in another. This is **deadlock-safe**: you
can chain multiple streaming operations without worrying about buffer
sizes.

The streaming model is inherited from
[scout-essentials' ConcurrentStream](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/StreamingModel.md).

## Persist as cache

Every workflow job result is saved as a file under `var/jobs/...`
automatically, so re-running a job reuses its previous output. For
explicit caching of in-memory computations, scout-essentials provides
`Persist.persist`/`Persist.memory`.

In scout-gear, the typical caching entry points are:

```ruby
# Idiomatic: TSV.open with persist (routes through Persist.tsv → HDB engine)
index = TSV.open("genes.tsv", persist: true).index(target: "GeneName")

# Idiomatic: explicit engine object, runs once across processes
index = Persist.persist("gene_index", :HDB, prefix: "v1") do |filename|
  Persist.open_database(filename, true, :marshal, "HDB")
end

# Non-idiomatic: recompute every time
def get_index                        # WRONG: no caching
  TSV.open("genes.tsv").index
end
```

The persistence key includes the prefix, which lets you version caches.
Change the prefix when the logic changes.

Two footguns documented in [Caching Data](../user/CachingData.md):

- `Persist.persist(name, :HDB)` with a block returning a plain Hash does
  **not** cache across calls: the `:HDB` save driver expects an engine
  object, the save fails, and the block re-runs every time. Return an
  engine object (`Persist.open_database`) or use `Persist.tsv`.
- A relative custom `:dir` for `Persist.persist` is not located, so
  cross-process cache hits require the default (located) cache dir or an
  absolute `:path`.

## Convention over configuration

Paths are derived from conventions, not configured. For example:
- Job results: `var/jobs/<Workflow>/<task>/<name>_<md5>.<ext>`
- Persisted caches: `~/.scout/var/cache/persistence/...`
- Identifier files: resolved from the entity's `identifier_files`
  annotations

This eliminates boilerplate. The convention is: if you follow the naming
convention, things work automatically. If you fight the convention, you
need to configure everything manually.

## Helper pattern

Tasks define reusable logic in helpers, which are methods available inside
task bodies:

```ruby
helper :normalize do |values|
  sum = values.map(&:to_f).sum
  (sum == 0) ? values : values.map { |v| v.to_f / sum }
end

task :normalized => :tsv do
  data = TSV.open(inputs[:file])
  TSV.traverse(data, into: :tsv) do |key, values|
    [key, normalize(values)]
  end
end
```

Helpers are defined with `helper(name, &block)` in the workflow module
(`workflow/definition.rb:39-44`) and stored in the workflow's `helpers`
annotation. Calling an undefined helper raises `ScoutException`
("helper … unknown in … workflow"). Helpers are shared across all tasks
in the workflow and merged into including workflows by
`include_workflow` (`workflow/definition.rb:240`). There is no
`helpers/` directory convention — helpers are defined in the workflow
file itself.

## Idiomatic vs non-idiomatic patterns

### Creating a TSV

```ruby
# Idiomatic
data = {"a" => [["1"]]}
TSV.setup(data, type: :double)

# Non-idiomatic
tsv = TSV.new                       # WRONG: TSV.new doesn't exist
```

### Indexing a TSV

```ruby
# Idiomatic (instance method delegates to class method, tsv/index.rb:111)
index = TSV.index(tsv, target: "GeneName")
# or
index = tsv.index(target: "GeneName")

# Non-idiomatic
index = {}
tsv.each { |k, v| index[k] = v[0] }  # WRONG: manual indexing
```

### Defining entity properties

```ruby
# Idiomatic
property :name do
  translate "Ensembl ID", "Gene Symbol"
end

# Non-idiomatic
def name                             # WRONG: bypasses property dispatch
  @name ||= lookup_name(self)
end
```

### Streaming between tasks

```ruby
# Idiomatic
dep :upstream, compute: :stream
task :downstream => :tsv do
  TSV.traverse(step(:upstream).load, into: :tsv) { |k, v| ... }
end

# Non-idiomatic
dep :upstream
task :downstream => :task
  data = step(:upstream).load   # materializes the entire result
  # ... then process
end
```

### Raising ScoutException vs plain errors

`ScoutException` and its subclasses mean **non-recoverable**: the same
call with the same inputs will always fail the same way, so the engine
neither cleans nor retries the step (`recoverable_error?`,
`step/status.rb:19-21`). Environmental problems — no read permission, no
network, a missing key — can be fixed and retried; raise them as plain
errors so the step stays retryable.

```ruby
# Idiomatic
task :sum => :numeric do |values|
  raise ParameterException, "values must all be numeric" unless values.compact.all?{|v| Numeric === v }   # bad input parameter: ScoutException
end

# Non-idiomatic
task :fetch => :string do
  raise ParameterException, "server_url not in config keys"   # WRONG: missing config key is environmental, recoverable
end
```

Input parameters and config keys are distinct: `ParameterException` is
for invalid task *input parameters* only; a missing *config key* is
recoverable state — fix the config and retry — which is why the API
calls them "config keys" and not "parameters". For the full engine
behavior see [Workflow Engine](WorkflowEngine.md), "Error classes and
recoverability".

## Common anti-patterns

1. **Creating wrapper classes around TSV** — Use annotations instead. If
   you need custom behavior, add methods via `TSV.setup` or reopen the TSV
   module.

2. **Loading data to process it** — Always use `traverse` with `into:`.
   If you find yourself writing `tsv.each` in new code, consider whether
   `traverse` would be more appropriate.

3. **Manual cache management** — Don't write custom caching logic. Use
   `Persist.persist`, `Persist.tsv`, or the `persist:` option on TSV
   operations.

4. **Subclassing instead of annotating** — If you need to attach behavior
   to an object, use annotations (`TSV.setup`, `Entity`, `Annotation`).
   Don't create new classes.

5. **Ignoring streaming dependencies** — When a task depends on another,
   consider whether the dependency should stream. Use `compute: :stream`
   to avoid materializing large results.

6. **Using instance `tsv.traverse(..., cpus:)`** — the instance method
   does not accept `cpus:`/`into:`; use the class method
   `TSV.traverse(tsv, cpus: N, into: target)`.

## See also

- [Architecture](Architecture.md)
- [TSV Internals](TSVInternals.md)
- [Caching Data](../user/CachingData.md)
- [Building Workflows](../user/BuildingWorkflows.md)
