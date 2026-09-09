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
- `entity_options` — Entity type options. Not preserved across
  dump/reload: `Dumper.header` serializes the option set through
  `IndiferentHash.hash2string`, which skips non-Scalar values, so a
  Hash-valued `entity_options` never reaches the `#:` preamble, and
  nothing on the read side restores it.
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
- `:double` — Each value column is split on `sep2` (`"|"` by default,
  `parser.rb:29`) into sub-arrays. `sep2` applies to *values* only for
  `:double`: a `:list` TSV never splits its values on `sep2`, so
  `"x|y"` survives intact in a `:list` column.

### Entry points

`TSV.open(file, options = {})` (`tsv.rb:75`) is the materializing entry
point; it accepts a filename/`Path`/`StringIO`/`TSV::Parser` and returns
an annotated Hash. Note that `TSV.open(tsv)` on an already-loaded TSV
re-opens its serialized stream and returns a **copy** — identity is lost
even though keys, fields and type survive; there is no `TSV.get` alias.

The lower-level, stream-first entry points live on `TSV::Parser`
(`parser.rb`) and are useful when you never want a Hash:

- `TSV::Parser.new(source, options)` — wraps a source without parsing it;
  the object answers `key_field`/`fields`/`type` immediately (header
  parsed lazily) and can be handed to `TSV.traverse`, `attach`, or a
  `TSV::Transformer`.
- `TSV.parse(stream, **kwargs, &block)` (`parser.rb:471`) — parses into
  a Hash, or into `data:` if given.
- `TSV.parse_stream(stream, **kwargs, &block)` (`parser.rb:74`) — yields
  `key, values` pairs without building a Hash.
- `TSV.parse_header(stream, fix: true, header_hash: '#', sep: "\t")`
  (`parser.rb:257`) — returns the parsed header options (including
  `all_fields`) without touching the data.
- `TSV.parse_line(line, type: :list, key: 0, positions: nil, sep: "\t",
  sep2: "|", cast: nil, select: nil, field_names: nil)` (`parser.rb:29`)
  — the single-row workhorse used by everything above.

### Field resolution and the object-level `identify_field`

Field names resolve through three surface-level helpers that share one
back-end, `TSV.identify_field(key_field, fields, name, strict: nil)`
(`tsv/util.rb:47`): `:key` matches literally (or the key field name when
`strict:` is falsy), everything else goes through
`NamedArray.identify_name`, which tolerates `Symbol`/`String` and the
standard header normalization. The wrappers are:

- `TSV#identify_field(name, strict: nil)` (`tsv/util.rb:53`) — on a
  materialized TSV.
- `TSV::Parser#identify_field(name)` (`parser.rb:375`) — **one
  positional argument only**; it delegates to the same back-end without
  forwarding `strict:`.
- `TSV::Transformer#identify_field(name)` (`transformer.rb:65`) — same
  shape as the Parser one.
- `TSV.identify_field_in_obj(obj, field)` (`change_id/translate.rb:3`)
  — dispatches on the object kind, accepting a TSV, Parser, Dumper, a
  path/`String` (whose header is parsed on the fly), or an
  `[key_field, *fields]` Array.

Because the Parser/Transformer wrappers take a single argument, code
that needs `strict:` must call the module method with
`obj.key_field`/`obj.fields` explicitly.

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
it to the pipe. The header is **not** written at construction: `init`
(which emits the `#:` preamble and the field-name line) runs at the first
`add`, so a Dumper that never receives a row produces an empty stream
(`close` on a fresh Dumper yields EOF with no header). The write API is
exactly `add`/`init`/`close`/`abort`; `stream` (`dumper.rb:124`) exposes
the read end.

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

Consequences worth knowing before you materialize one:

- A **String source is a file path** — `TSV::Transformer.new("a|b")`
  fails with `Errno::ENOENT`; hand it a `Path`, a filename that exists,
  a `TSV`, or a `Parser`.
- Nothing is produced until `traverse`/`each` runs. Calling `.tsv` on a
  Transformer that was never traversed **blocks forever** reading a pipe
  whose writer never closes (the Dumper is still `initialized == false`);
  run `traverse { |k,v| [k,v] }` first.
- `transformer.traverse` routes block results into the dumper through
  `traverse_add`, so a block returning `nil` writes nothing.
- `.tsv` re-parses the dumper stream into a Hash-backed TSV when the
  target is the built-in Dumper, and returns the target object itself
  (identity preserved) when the target is a TSV. `.stream` on a Dumper
  target is the IO pipe carrying the TSV text.

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
`into:` keywords. The block yields `(key, values)` — values are a
`NamedArray` carrying the field names unless the TSV is `unnamed` — and
the **return value is `[key_name, field_names]`** of the traversal
(`traverse.rb:164`), not a data structure. A 3-arity block still gets
`nil` as its third argument (field names are not yielded).

### Class method: `TSV.traverse`

`lib/scout/tsv/open.rb:36`:

```ruby
TSV.traverse(obj, into: nil, cpus: nil, bar: nil, callback: nil,
             unnamed: true, keep_open: false, **options, &block)
```

The parallel/streaming workhorse. `obj` can be a TSV, a filename, a
stream, or a `Parser`. `into` accepts a concrete target object — Hash,
TSV, Array, Set, IO/`StringIO`, `TSV::Dumper`, a `Path` (written with
`Open.write`), or the symbol `:stream` (which wraps an `Open.pipe` and
returns the read end) — and results are added via `traverse_add`
(`tsv/open.rb:12-34`), which handles `MultipleResult` unwrapping (a row
yielding `MultipleResult.setup([...])` produces several rows). Symbols
are **not** general targets: `into: :tsv` falls through the
`traverse_add` `case` untouched, so nothing is collected and the symbol
itself is returned.

`into:` decides the *return value*: with no `into:`, block results are
discarded and the return is whatever the source branch produced — the
header pair `[key_field, fields]` for a TSV/`Parser` source
(`tsv/traverse.rb:164`), or the (empty) parsed container for a
stream/StringIO (`TSV.parse`, `tsv/open.rb:187`); with `into:`, the call
returns the target itself (`into || res`, `tsv/open.rb:202`), so the
result is the very object that was passed in. A Hash target accumulates
`key => value` (a `:double` TSV target merges with `zip_new`); an
Array/Set target appends whole `[key, values]` rows (`into << res`); an
`IO`/StringIO target receives one `puts` per result.

When a `callback:` is supplied alongside `cpus:`, the callback receives
each worker result **from the main process** as it arrives over the
output socket — ordering is completion order, not source order. Without
`cpus:` (single-process traverse) the callback runs per row in source
order. Ordering under `cpus:` is therefore not contractual.

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

`fields:` controls which source columns are indexed — it defaults to
`:all`, so *every* column value of the source becomes an index key even
when `target:` names a single column (with `target: :key`, the default,
the key itself, the `GeneName` values and the `V` values all map to the
row key). An explicit `fields: ["GeneName"]` restricts indexing to that
column. The index is write-once per value: when a source value appears
in several rows the **first row seen wins** under both `order:` settings
— `order: true` (default) collects with `uniq.first` over a `:double`
traverse, `order: false` uses a flat traverse that skips values already
present; they differ only in memory layout. The index's `key_field` is
the comma-joined list of indexed source column names (so `ID,GeneName,V`
with `fields: :all`) and its single field is the target column name.
With `persist: true` the returned object is a `TokyoCabinet::HDB`
(through `ScoutCabinet` + `TSVAdapter`); without it, a plain annotated
Hash.

The instance method `tsv.index` delegates to the class method
(`tsv/index.rb:111`).

`TSV.index` also answers for the **key column**: the default target
`:key` maps every distinct value of the indexed columns to its row key,
and `fields: :all` (the default) includes the key itself in the indexed
set. Passing `fields: ["X"]` limits the index to that column.

### Range index

A range index supports queries for all entries overlapping a coordinate
range. Built with:

```ruby
TSV.range_index(tsv, "Start", "End")
```

`TSV.range_index` (`tsv/index.rb:115`) takes `start_field`, `end_field`
positionally plus `key_field: :key`. This creates a `FixWidthTable` that
stores start/end positions for each key, allowing fast range queries.
Used for genomic coordinate lookups. `TSV.pos_index` (`tsv/index.rb:159`)
is the single-coordinate analogue.

### Index persistence

Indexes can be persisted:
```ruby
TSV.index(tsv, target: "GeneName", persist: true, engine: :HDB)
```

The persistence path is derived from the source file path and the index
options (prefix includes the target/fields, `index.rb:48-53`).

## Identifier translation

Identifier files are ordinary TSVs whose **header field names are the
identifier formats** they map between (`#Name,Alias,ID` maps between all
three). The source/target pair is chosen at translation time from the
file's columns — there is no per-pair file naming and no implicit
directory scan. Files reach the TSV layer from the `identifiers:` option,
entity-declared files (`add_identifiers`, `entity/identifiers.rb:84`), or
auto-discovery of an `identifiers` entry next to the TSV's file
(`tsv/path.rb:14-21`).

The core is `TSV.translation_index(files, source, target)`
(`tsv/change_id/translate.rb:49`): `translation_path` (line 20) picks a
chain of up to three files whose columns bridge source to target, the
first is keyed on `source`, the rest are attached in sequence, and the
result is sliced to the target column and persisted (`HDB`). The data TSV
itself may participate in the chain. `TSV.translate` (line 116) applies
the index and rewrites headers; parenthesized headers
`Label (Format)` keep the label and swap the format.

`change_id`/`change_key` (`tsv/change_id.rb`) are attach-based wrappers,
and `attach` itself builds such an index automatically when the two
tables' keys do not match (`tsv/attach.rb:79-87`).

Translation handles missing entries by leaving the original value in
place (the row is not dropped, and unmatched keys survive as
`nil`-free rows). `TSV.translation_index` caches its result under
`~/.scout/var/cache/persistence` with a `Translation_index:` prefix, so
a previously built chain of identifier files is reused without rebuilding.
`stream: true` on `tsv.translate`/`tsv.change_key` returns a
`TSV::Transformer` instead of a materialized TSV.

## Attach / Join

The `attach` method (`tsv/attach.rb:228`) adds columns from one TSV to
another by matching on a key. The matching key is auto-detected:

1. If a matching field is specified, use it.
2. Otherwise, look for a common field name between the source and target.
3. If no common field is found, look for identifier files that can
   translate.

Attach uses indexes to avoid full scans (it builds a translation index
from identifier files when the keys do not line up,
`tsv/attach.rb:78-86`). The receiver decides the result:

- On an in-memory TSV, `tsv.attach(other)` mutates **and returns the
  receiver** — the attached columns are appended to `tsv.fields` and
  missing matches produce a `nil` entry in the row.
- On a `Parser`/filename source, `target:` selects the destination:
  `target: :stream` returns a `TSV::Dumper`-backed TSV whose `to_s`
  renders the merged table (consume the stream, then `TSV.open(stream)`
  to materialize); `target: nil` returns a materialized TSV; any other
  object is used as the write target.
- `complete: true` adds rows for keys that exist only in the attached
  TSV (their source columns are `nil`); `match_key:` names the source
  column the other TSV's key is matched against; there is no `field:`
  keyword — column selection is `fields:`.

`attach` streams: the attached TSV is traversed and merged via a Dumper
rather than materialized wholesale.

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
- `sep2` defaults to `"|"` in `parse_line` (`parser.rb:29`). Dumping
  always *rejoins* sub-values with a literal `"|"`, regardless of the
  `sep2` the TSV was opened with, and the `#: :sep2=` directive is not
  written into the preamble — so a non-default `sep2` is effectively a
  read-side option. If you need round-trip fidelity, normalize to `|`
  on write. (Redeclaring `sep2:` at open does work: a directive value
  must be quoted — `#: :sep2=':'` — because a bare `:` is read back as
  a Symbol.)
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
