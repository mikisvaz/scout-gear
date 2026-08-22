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
- `entity_options` — Entity type options.
- `identifiers` — Identifier translation files (set via `TSV#identifiers=`
  / `Entity::Identified` conventions; see `Entity System`).

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
- `:double` — Columns are split on `sep2` (`","` by default) into
  sub-arrays.

## Streaming: Dumper and Transformer

### Dumper

The `Dumper` (`lib/scout/tsv/dumper.rb:30-46`) is the output side of a
streaming TSV operation. It creates an `Open.pipe` pair, annotates both
ends as ConcurrentStreams, and provides `add(key, value)` (:88) plus
`init(preamble: true)` (:80) which writes the header line.

A Dumper maintains:
- A `key_field` and `fields` (for the header line).
- An `@sout/@sin` pipe pair (replaced if `set_stream` is called).
- A `sep` (field separator, default `\t`) and `type` (default `:double`).

When you call `dumper.add(key, values)`, it serializes the row and writes
it to the pipe. The header is written first.

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

There are two traverse APIs, and they differ:

### Instance method: `TSV#traverse`

`lib/scout/tsv/traverse.rb:3`:

```ruby
tsv.traverse(key_field_pos = :key, fields_pos = nil,
             type: nil, one2one: false, unnamed: nil,
             key_field: nil, fields: nil, bar: false,
             cast: nil, select: nil, uniq: false, &block)
```

Iterates rows of an already-loaded TSV with field selection, type
conversion, filtering, and `one2one` checking (with `:strict` mode for
error-on-duplicate keys, `traverse.rb:90-91`). It has **no** `cpus:` or
`into:` keywords.

### Class method: `TSV.traverse`

`lib/scout/tsv/open.rb:36`:

```ruby
TSV.traverse(obj, into: nil, cpus: nil, bar: nil, callback: nil,
             unnamed: true, keep_open: false, **options, &block)
```

The parallel/streaming workhorse. `obj` can be a TSV, a filename, a
stream, or a `Parser`. `into` accepts a wide range of targets — Hash,
Array, Set, IO, `TSV::Dumper`, a `Parser`/stream to chain, `:tsv`/`:flat`
shorthands — and results are added via `traverse_add`
(`tsv/open.rb:12-34`), which handles `MultipleResult` unwrapping (a row
yielding `MultipleResult.setup([...])` produces several rows).

When `cpus:` is specified (and > 1), traverse uses WorkQueue to
distribute rows across forked worker processes:

1. The main process reads rows from the source.
2. Rows are distributed to workers via IPC sockets.
3. Workers execute the block and return results.
4. Results flow through the output socket back to the main process.
5. The `into:` target receives results from the main process.

Work items and results must be Marshal-serializable. (The *block* itself
is not marshalled — workers are forked and inherit it.) Each worker is a
forked process with its own memory space.

## Indexing

### Point index

A point index maps a key to a single value. Built with:

```ruby
TSV.index(tsv, target: "GeneName")
```

`TSV.index` (`tsv/index.rb:40`) accepts `target:` (default `:key`),
`fields:`, `order:`, `bar:`, plus persistence options. The index prefix
is `Index[fields->target]` (or `Index[target]` when `fields: :all`), and
it is persisted through `Persist.persist` with engine `:HDB` by default
(`persist => false` unless explicitly requested) — the built index is a
`ScoutCabinet` extended with `TSVAdapter`, or a plain annotated Hash when
no filename is given (`index.rb:60-68`).

The instance method `tsv.index` delegates to the class method
(`tsv/index.rb:111`).

### Range index

A range index supports queries for all entries overlapping a coordinate
range. Built with:

```ruby
TSV.range_index(tsv, "Start", "End")
```

`TSV.range_index` (`tsv/index.rb:115`) takes `start_field`, `end_field`
positionally plus `key_field: :key`. This creates a `FixWidthTable` that
stores start/end positions for each key, allowing fast range queries.
Used for genomic coordinate lookups.

### Index persistence

Indexes can be persisted:
```ruby
TSV.index(tsv, target: "GeneName", persist: true, engine: :HDB)
```

The persistence path is derived from the source file path and the index
options (prefix includes the target/fields, `index.rb:48-53`).

## Identifier translation

The TSV system supports identifier translation. Identifier files are
registered on entity modules via `add_identifiers`
(`entity/identifiers.rb:85`) or located through the entity's
`identifier_files` list; there is no implicit `var/<namespace>/identifiers/`
directory scan.

The `change_id` method (`tsv/change_id.rb:43`) translates keys or field
values using these identifier files.

The `attach` method can use identifier files to join tables with
incompatible keys.

## Attach / Join

The `attach` method (`tsv/attach.rb:228`) adds columns from one TSV to
another by matching on a key. The matching key is auto-detected:

1. If a matching field is specified, use it.
2. Otherwise, look for a common field name between the source and target.
3. If no common field is found, look for identifier files that can
   translate.

Attach uses indexes to avoid full scans. The result is a new TSV with the
attached columns. `attach` streams: the attached TSV is traversed and
merged via a Dumper rather than materialized wholesale.

## Serialization and persistence

TSV data is serialized via `TSVAdapter` (in `lib/scout/persist/tsv/`).
The adapter:

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

To use a custom object as an `into:` target for the class method, make it
respond to `<<` (and optionally `close`/`abort`):

```ruby
class MyCollector
  def <<(row)
    # row is [key, values]
  end
end

result = TSV.traverse(tsv, into: MyCollector.new) { |k, v| [k, v] }
```

## Known issues

- The `attach` auto-detection of match keys can produce surprising results
  when multiple fields could match.
- Large `:double`-type TSVs with deeply nested values can have slow parsing.
- `sep2` is `,` by default here, while some scout-essentials data uses `;`
  — watch for this when sharing files between repositories.
- The `namespace` annotation is used inconsistently — sometimes it's a
  module name, sometimes it's a path.

## See also

- [Architecture](Architecture.md)
- [Persistence Engines](PersistenceEngines.md)
- [Concurrency Model](ConcurrencyModel.md)
- [Processing Tabular Data](../user/ProcessingTabularData.md)
- [Entity System](EntitySystem.md)
- [scout-essentials: Streaming Model](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/StreamingModel.md)
- [scout-essentials: Annotation System](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/AnnotationSystem.md)
