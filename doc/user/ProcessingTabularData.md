# Processing Tabular Data

This document explains how to work with tabular data in scout-gear. It
covers opening existing data, creating new tables, transforming rows,
filtering, restructuring, and streaming large datasets.

It is intended for workflow authors and data analysts who need to process
structured data.

## What problem does this solve?

Tabular data — keyed rows with typed columns — is the most common data
format in bioinformatics and data analysis. You need to:

- Parse TSV/CSV files efficiently, including headers and type annotations.
- Process data row by row without loading everything into memory.
- Join tables, filter rows, translate identifiers, and restructure columns.
- Persist processed data to disk for reuse.

The TSV system in scout-gear provides all of this with a streaming-first
architecture. Operations like join, filter, and transform are
**deadlock-safe** — they use pipes and threads, not recursion, to move data.

## When do I use it?

- When you have TSV or CSV data that needs processing.
- When you need to join or attach columns from one table to another.
- When your data is too large to fit in memory and you need streaming.
- When you need type-aware operations (integer columns, float columns, etc.).

## Core concepts

### TSV

A TSV is a Hash-like object where each key maps to one or more values. The
"value type" determines how columns are structured:

| Value type | Structure | Example value for one key |
|------------|-----------|---------------------------|
| `:single` | One value per key | `"42"` |
| `:list` | Array of values per key | `["42", "yes"]` |
| `:flat` | Flat array (no field names) | `["a", "b", "c"]` |
| `:double` | Array of arrays | `[["a"], ["b"]]` |

A TSV also carries metadata: key field name, field names, namespace, and
data type. This metadata is preserved through operations.

### Opening a file

```ruby
tsv = TSV.open("data.tsv", type: :list, sep: "\t")
```

Options include:

| Option | Purpose |
|--------|---------|
| `type:` | Value type (`:single`, `:list`, `:flat`, `:double`) |
| `sep:` | Field separator (default: `\t`) |
| `key_field:` | Which column is the key (name or index) |
| `fields:` | Which columns to load (names or indices) |
| `cast:` | Convert values (`:to_i`, `:to_f`) |
| `select:` | Filter rows by field values |
| `persist:` | Persist to a database for reuse |
| `engine:` | Persistence engine (see [Caching Data](CachingData.md)) |

### Creating a TSV from scratch

```ruby
data = {
  "gene1" => ["100", "up"],
  "gene2" => ["200", "down"],
}

TSV.setup(data, type: :list, key_field: "Gene", fields: ["Expression", "Change"])
```

## Transforming data

### Traverse

The `traverse` method iterates over rows with optional field selection,
type conversion, and filtering. It is the primary way to process rows.

```ruby
# Iterate over rows
tsv.traverse do |key, values|
  puts "#{key}: #{values * ", "}"
end

# Select specific fields and type
tsv.traverse(key_field: "Gene", fields: ["Expression"], type: :single) do |gene, expression|
  puts "#{gene} has expression #{expression}"
end
```

### Streaming transform with `into:`

Use `into:` to direct the output of a traverse into a new TSV, a file,
or any object that accepts `<<`:

```ruby
# Create a new TSV by transforming rows
result = tsv.traverse(:key, :into => :tsv) do |key, values|
  [key, values.map { |v| v.to_i * 2 }]
end
```

The `into:` target can be:

| Target | Result |
|--------|--------|
| `:tsv` | A new TSV object |
| `:dumper` | A TSV stream (can be piped to other operations) |
| `:array` | An array of `[key, values]` pairs |
| `:hash` | A hash of `key => values` |
| Any object with `<<` | Results are written via `<<` |

### Parallel processing

Use `cpus:` to distribute work across multiple processes:

```ruby
result = tsv.traverse(:key, into: :tsv, cpus: 4) do |key, values|
  [key, expensive_compute(values)]
end
```

This forks N worker processes and distributes rows across them. Results
are collected automatically.

## Filtering

### Select and reject

```ruby
# Filter by specific field values
filtered = tsv.select("Change" => ["up"])

# Reject specific values
rejected = tsv.reject("Change" => ["down"])
```

### Filtering within traverse

```ruby
tsv.traverse(select: {"Change" => ["up"]}) do |key, values|
  # Only rows where Change == "up"
end
```

## Restructuring

### Slice (select columns)

```ruby
subset = tsv.slice(fields: ["Gene", "Expression"])
```

### Reorder (change key column)

```ruby
by_expression = tsv.reorder("Expression")
```

### Merge duplicate keys

```ruby
merged = tsv.attach(other_tsv, fields: ["NewColumn"])
```

## Joining tables (attach)

The `attach` operation adds columns from one TSV to another, joining on a
common key. It automatically detects the matching key.

```ruby
# Add "Protein" column from another TSV
result = tsv.attach(protein_tsv, fields: ["Protein"])

# Explicit match keys
result = tsv.attach(protein_tsv, fields: ["Protein"], match_key: "GeneID", other_key: "EnsemblID")
```

If the tables don't share a common key field, attach can use identifier
translation files automatically. Provide `identifiers:` to specify a
translation file.

## Translating identifiers

```ruby
# Translate gene IDs to gene names
file_with_translated_ids = FileExchanger.translate_identifiers(tsv, "GeneID", "GeneName")
```

The `change_id` operation translates keys or field values using identifier
files that follow the convention:
```
var/<namespace>/identifiers/<source_format>%to<target_format>
```

## Indexing

Build an index for fast lookups:

```ruby
# Point index (key → single value)
index = TSV.index(tsv, target: "GeneName")
index["ENSG00000141510"]  # => "TP53"

# Range index (for coordinate-based lookups)
index = TSV.range_index(tsv, "start", "end")
index.range("chr1", 100000, 200000)  # => all entries overlapping this range
```

## Persisting processed data

For large datasets, persist processed data to a database:

```ruby
tsv = TSV.open("huge_file.tsv", persist: true, engine: :HDB)
# First load populates the database; subsequent loads read from it
```

See [Caching Data](CachingData.md) for details on engine selection and
persistence options.

## Common mistakes

- **Loading everything into memory**: For large files, use `persist: true`
  or process with `traverse` and `into:` instead of loading the whole TSV.
- **Wrong value type**: If your data has multiple values per cell, use
  `:list` or `:double`, not `:single`. Check with `tsv.type`.
- **Expecting `traverse` to modify in place**: `traverse` iterates; it
  doesn't change the original. Use `into: :tsv` to produce a new TSV.
- **Forgetting to close streams**: When using `into: :dumper` or a custom
  IO target, the stream must be closed (usually by consuming it or calling
  `.join` on the result).
- **Non-serializable blocks in parallel traverse**: When using `cpus:`,
  the block is serialized to worker processes. Avoid capturing non-Marshal-
  serializable objects.
- **Attach with incompatible keys**: If `attach` can't find a matching key,
  it may silently produce empty results. Always check the output.

## See also

- [scout-essentials: Handling Streams](https://github.com/mikisvaz/scout-essentials/blob/main/doc/user/HandlingStreams.md)
- [scout-essentials: Caching Results](https://github.com/mikisvaz/scout-essentials/blob/main/doc/user/CachingResults.md)
- [Building Workflows](BuildingWorkflows.md)
- [Caching Data](CachingData.md)
- [Working with Entities](WorkingWithEntities.md)
- [Cookbook](Cookbook.md)
