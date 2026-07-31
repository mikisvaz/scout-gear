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
Pathname with annotations. A Task is a Module with annotations.

**Why?** Because annotation preserves duck-typing. A TSV can be passed to
any function that expects a Hash. An Entity can be passed to any function
that expects a String. Subclassing breaks this.

## Stream, don't load

When processing large datasets, never load the entire dataset into memory.
Instead, use the traverse API to process rows one at a time, streaming
results through pipes.

```ruby
# Idiomatic: streaming transform
result = tsv.traverse(:key, into: :tsv) do |key, values|
  [key, transform(values)]
end

# Non-idiomatic: load everything, then transform
new_hash = {}
tsv.each do |key, values|          # WRONG: loads everything
  new_hash[key] = transform(values)
end
```

The traverse API uses a Dumper/Transformer pair that writes to a pipe in
one thread and reads from it in another. This is **deadlock-safe**: you
can chain multiple streaming operations without worrying about buffer
sizes.

The streaming model is inherited from
[scout-essentials' ConcurrentStream](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/StreamingModel.md).

## Persist as cache

Every workflow result is persisted automatically. For explicit caching,
wrap expensive computations in `Persist.persist`:

```ruby
# Idiomatic: cache the result
index = Persist.persist("gene_index", :HDB, prefix: "v1") do
  TSV.open("genes.tsv").index
end

# Non-idiomatic: recompute every time
def get_index                        # WRONG: no caching
  TSV.open("genes.tsv").index
end
```

The persistence key includes the prefix, which lets you version caches.
Change the prefix when the logic changes.

## Convention over configuration

Paths are derived from conventions, not configured. For example:
- Job results: `var/jobs/<Workflow>/<task>/<digest>.<ext>`
- Persisted databases: `var/databases/...`
- Identifier files: `var/<namespace>/identifiers/<source>%to<target>`

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
  data = TSV.open(input[:file])
  data.traverse(:key, annotate_into: :tsv) do |key, values|
    [key, normalize(values)]
  end
end
```

Helpers can be defined in the workflow module or in `helpers` directory.
They are shared across all tasks in the workflow.

## Idiomatic vs non-idiomatic patterns

### Creating a TSV

```ruby
# Idiomatic
data = {"a" => [1]}
TSV.setup(data, type: :list)

# Non-idiomatic
tsv = TSV.new                       # WRONG: TSV.new doesn't exist
```

### Indexing a TSV

```ruby
# Idiomatic
index = TSV.index(tsv, target: "GeneName")

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
  step(:upstream).load.traverse(:key, into: :tsv) { |k, v| ... }
end

# Non-idiomatic
dep :upstream
task :downstream => :task
  data = step(:upstream).load   # WRONG: materializes the entire result
  # ... then process
end
```

## Common anti-patterns

1. **Creating wrapper classes around TSV** — Use annotations instead. If
   you need custom behavior, add methods via `TSV.setup` or reopen the TSV
   module.

2. **Loading data to process it** — Always use `traverse` with `into:`. If
   you find yourself writing `tsv.each` in new code, consider whether
   `traverse` would be more appropriate.

3. **Manual cache management** — Don't write custom caching logic. Use
   `Persist.persist` or the `persist:` option on TSV operations.

4. **Subclassing instead of annotating** — If you need to attach behavior
   to an object, use `Annotation.annotate` or `Entity.extend`. Don't
   create new classes.

5. **Ignoring streaming dependencies** — When a task depends on another,
   consider whether the dependency should stream. Use `compute: :stream`
   to avoid materializing large results.

## See also

- [Architecture](Architecture.md)
- [Research: Design Philosophy Analysis](../../research/design-philosophy-analysis.md)
- [scout-essentials: Design Principles](https://github.com/mikisvaz/scout-essentials/blob/main/doc/research/design-philosophy-analysis.md)
