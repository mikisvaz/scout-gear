# TSV Internals

This document describes the internal architecture of the TSV system.

It is designed for framework contributors who need to understand or extend
the tabular data processing pipeline.

## Overview

The TSV system is scout-gear's data processing engine. It provides parsing,
transformation, streaming, indexing, and persistence of tabular data. It
is built on scout-essentials' `Annotation` and `ConcurrentStream`.

A TSV is a plain Ruby Hash annotated with metadata (key field name, field
names, value type, namespace). The metadata is carried as annotations,
not instance variables, so a TSV retains all Hash behavior.

## Data model

### Value types

A TSV can have four value types:

| Type | Structure | One key maps to |
|------|-----------|-----------------|
| `:single` | Scalar | One value |
| `:list` | Array | Array of values (one per field) |
| `:flat` | Flat array | Array of values (no field names) |
| `:double` | Nested array | Array of arrays (multiple values per field) |

### Annotations

A TSV carries these annotations:
- `key_field` — Name of the key column.
- `fields` — Array of field names.
- `namespace` — Namespace for identifier translation.
- `type` — Value type (`:single`, `:list`, `:flat`, `:double`).
- `identifier_files` — List of identifier translation files.
- `entity_options` — Entity type options.

## Parsing pipeline

The parsing pipeline is defined in `lib/scout/tsv/parser.rb`:

```
Source (file/stream)
   │
   ▼
┌──────────┐     ┌──────────────────────┐     ┌──────────┐
│  Open    │────▶│  Parser              │────▶│  Hash    │
│ (source) │     │  - skip comments     │     │ (annotated)
│          │     │  - detect header     │     │
└──────────┘     │  - parse key field   │     └──────────┘
                  │  - parse values      │
                  │  - apply cast        │
                  └──────────────────────┘
```

1. The source is opened via scout-essentials' `Open` (which handles HTTP,
   compression, local files, etc.).
2. Comment lines (starting with `#`) are skipped.
3. The first non-comment line is the header.
4. Each subsequent line is split on the separator, and key/values are
   extracted based on the value type.
5. Optional `cast:` converts values to integers or floats.

### Parsing details

The parser uses `parse_line` for each row. Key extraction depends on the
type:
- `:single` — First column is key, second column is value.
- `:list` — First column is key, remaining columns form an array.
- `:flat` — First column is key, remaining columns form a flat array.
- `:double` — Columns are split on `sep2` (";" by default) into sub-arrays.

## Streaming: Dumper and Transformer

### Dumper

The `Dumper` is the output side of a streaming TSV operation. It wraps a
target object (a pipe, a file, an array) and provides a `<<` method that
serializes rows in TSV format.

A Dumper maintains:
- A `key_field` and `fields` (for the header line).
- An `out` target (the pipe or file).
- A `sep` (field separator, default `\t`).

When you call `dumper.add(key, values)`, it serializes the row and writes
it to `out` via `<<`. The header is written first.

### Transformer

A `Transformer` pairs a `Parser` (input side) with a `Dumper` (output
side) and a processing block. It reads rows from the parser, applies the
block, and writes results to the dumper.

The Transformer runs the parser and dumper in separate threads, connected
by a pipe. This is **deadlock-safe**:
- The parser thread reads from the source and writes to the pipe.
- The dumper thread reads from the pipe and writes to the target.
- The processing block runs in the parser thread.

This threading model means you can chain multiple Transformers without
worrying about buffer sizes or stack depth. Each Transformer is an
independent pipe stage.

### Concurrency safety

The streaming pipeline uses ConcurrentStream (from scout-essentials) for
IPC between threads and processes. The key safety guarantees:

1. **No recursive calls**: Data flows through pipes, not recursive
   function calls.
2. **Producer-consumer pattern**: Each pipe stage has one writer and one
   reader.
3. **Automatic closing**: Streams are closed when the producer finishes,
   signaling EOF to the consumer.

## Traverse

The `traverse` method is the primary data processing abstraction. It
iterates over rows with field selection, type conversion, filtering, and
parallel processing.

```ruby
tsv.traverse(
  key_field, fields,
  type: :list,
  one2one: false,
  unnamed: nil,
  select: nil,
  cpus: nil,
  into: nil,
  bar: false,
  cast: nil,
  &block
)
```

Key parameters:
- `key_field` / `fields` — Select specific columns; enables column
  re-selection without loading the full TSV.
- `type` — Convert value type during iteration.
- `one2one` — If true, the block must return exactly one row per input
  row (used for one-to-one transforms).
- `select` — Hash of field => [values] to filter rows.
- `cpus` — Fork N worker processes for parallel processing.
- `into` — Target for results (`:tsv`, `:dumper`, `:array`, `:hash`, or
  any object responding to `<<`).

### Parallel traverse

When `cpus:` is specified, traverse uses WorkQueue to distribute rows
across forked worker processes:

1. The main process reads rows from the source.
2. Rows are distributed to workers via IPC sockets.
3. Workers execute the block and return results.
4. Results flow through the output socket back to the main process.
5. The `into:` target receives results from the main process.

The block must be Marshal-serializable. Each worker is a forked process
with its own memory space.

## Indexing

### Point index

A point index maps a key to a single value. Built with:

```ruby
TSV.index(tsv, target: "GeneName")
```

Internally, the index is a TSV with a single field. It's typically
persisted to a database (HDB) for fast lookups.

### Range index

A range index supports queries for all entries overlapping a coordinate
range. Built with:

```ruby
TSV.range_index(tsv, "Start", "End")
```

This creates a `FixWidthTable` that stores start/end positions for each
key, allowing fast range queries. Used for genomic coordinate lookups.

### Index persistence

Indexes can be persisted:
```ruby
TSV.index(tsv, target: "GeneName", persist: true, engine: :HDB)
```

The persistence path is derived from the source file path and the index
options.

## Identifier translation

The TSV system supports identifier translation via convention-based files:

```
var/<namespace>/identifiers/<source>%to<target>
```

These are TSV files mapping one identifier format to another. The
`change_id` method translates keys or field values using these files.

The `attach` method can automatically use identifier files to join tables
with incompatible keys.

## Attach / Join

The `attach` method adds columns from one TSV to another by matching on a
key. The matching key is auto-detected:

1. If `match_key` is specified, use it.
2. Otherwise, look for a common field name between the source and target.
3. If no common field is found, look for identifier files that can
   translate.

Attach uses indexes to avoid full scans. The result is a new TSV with the
attached columns.

## Serialization and persistence

TSV data is serialized via `TSVAdapter` (in `lib/scout/persist/tsv`). The
adapter:

1. Serializes the TSV to a text format (TSV with header).
2. Stores it in a persistence engine (HDB, BDB, etc.).
3. On read, re-parses the text format and restores annotations.

The adapter preserves all metadata (key field, fields, type, namespace)
through serialization.

## Extension points

### Adding a new result type

To add a new value type (e.g., `:triple`):

1. Extend `TSV::Parser.parse_line` to handle the new type.
2. Extend `TSV::Dumper` to serialize the new type.
3. Ensure `TSVAdapter` handles it.

### Custom traverse targets

To use a custom object as an `into:` target, implement `<<`:

```ruby
class MyCollector
  def <<(row)
    # row is [key, values]
  end
end

result = tsv.traverse(:key, into: MyCollector.new) { |k, v| [k, v] }
```

## Known issues

- The `attach` auto-detection of match keys can produce surprising results
  when multiple fields could match.
- Large `:double`-type TSVs with deeply nested values can have slow parsing.
- Parallel traverse with non-Marshal-serializable blocks fails silently in
  some edge cases.
- The `namespace` annotation is used inconsistently — sometimes it's a
  module name, sometimes it's a path.

## See also

- [Architecture](Architecture.md)
- [Persistence Engines](PersistenceEngines.md)
- [Concurrency Model](ConcurrencyModel.md)
- [Research: TSV Internals Analysis](../../research/tsv-internals-analysis.md)
- [scout-essentials: Streaming Model](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/StreamingModel.md)
- [scout-essentials: Annotation System](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/AnnotationSystem.md)
