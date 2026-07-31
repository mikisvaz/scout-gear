# Investigation: TSV Internals

> **Non-normative.** This document is a working investigation with
> implementation details, code exploration notes, and hypotheses. Refer to
> `doc/developer/` for maintained architectural documentation.

## Overview

TSV is the central data structure in scout-gear. It represents tabular data
as a Hash-like object where keys map to values with type semantics. The
module mixes into Hash, Array, and String objects via the `TSV.setup`
annotation protocol inherited from scout-essentials.

## Data model: four value types

TSV supports four "value types" that determine how the columns of each row
are interpreted:

| Type | Value structure | Example |
|------|-----------------|---------|
| `:single` | A single value (String) | `"value"` |
| `:list` | An array of values per key | `["a", "b", "c"]` |
| `:flat` | A flat array (no field structure) | `["a", "b", "c"]` |
| `:double` | An array of arrays | `[["a"], ["b"], ["c"]]` |

These types affect parsing, serialization, and traversal. The type is stored
as the `:type` annotation and propagated through operations.

## Parsing pipeline

**`TSV::Parser`** (`lib/scout/tsv/parser.rb`):
- Reads a stream or file in TSV format
- Processes the header line: `key_field\tfield1\tfield2\t...`
- Uses `key_field`, `fields`, `type`, `sep`, `header_hash` (default `#`),
  `merge`, `cast`, `select`, `uniq` parser options
- Exposes `traverse` for streaming iteration

**Header parsing**:
The first non-comment line is the header. It is split on the separator (tab
by default). The first column is the `key_field`; the rest are `fields`.
Comments start with `header_hash` (usually `#`).

**Line parsing** (`parse_line`):
Each line is split on the separator. Key field extraction depends on the
type and whether `key_field` is at position 0 or elsewhere. For `:double`
type, fields are split on `|` into sub-lists.

## Dumper

**`TSV::Dumper`** (`lib/scout/tsv/dumper.rb`):
A Dumper is an object that produces a TSV stream. It wraps a
ConcurrentStream and writes header + rows to it. Key features:
- `add(key, values)` — writes a row to the output stream
- `init` — writes the header line
- `close` — finishes the stream
- Can be used as an `into:` target for `Open.traverse`
- The output stream is a ConcurrentStream that can be piped into other
  operations

## Transformer

**`TSV::Transformer`** (`lib/scout/tsv/transformer.rb`):
A Transformer connects a Parser (source) to a Dumper (sink). It is the
core streaming pipeline abstraction:
- Takes a Parser (any TSV or stream) and a Dumper (optional, auto-created)
- `traverse` method calls `Open.traverse(parser, into: dumper)` with the
  user's block applied to each row
- Each row is wrapped in a NamedArray (if fields are known) so the block
  can access fields by name
- The Transformer's `tsv` method materializes the stream into a TSV object
  (with persistence)

```ruby
# Typical Transformer usage
dumper = TSV::Dumper.new(source.options.merge(key_field: "NewKey"))
transformer = TSV::Transformer.new(source, dumper)
transformer.traverse do |key, values|
  # values is a NamedArray — access fields by name
  new_key = values["OriginalField"]
  [new_key, values]
end
result = transformer.tsv
```

## Traverse abstraction

**`TSV#traverse`** (`lib/scout/tsv/traverse.rb`):
Instance method on TSV objects for iterating over rows with field selection
and type conversion. Key options:
- `key_field`, `fields` — select which columns to emit
- `type` — convert value type during traversal
- `unnamed` — if false, values are NamedArrays
- `select` — filter rows by field values
- `one2one` — expect one value per key (no list wrapping)

**`Open.traverse`** (`lib/scout/tsv/open.rb`):
The polymorphic traverse engine. Accepts TSV, Hash, Array, IO, Step,
String (file path), or TSV::Parser. Key features:
- `into:` — directs results to a Dumper, TSV, Hash, Array, IO, or Path
- `cpus:` — parallel processing using WorkQueue (fork + IPC)
- `bar:` — progress bar integration
- `callback:` — called after each element
- Returns the `into` target (or last result if no `into`)

**Streaming architecture in Open.traverse**:
When `into` is a closable object (Dumper, IO), `Open.traverse` runs the
traversal in a background thread and returns immediately. The `into` object
is set up as a ConcurrentStream with the background thread attached. This
makes the pipeline deadlock-safe: producers and consumers run concurrently
in separate threads.

**Parallelization with WorkQueue**:
When `cpus:` is specified:
1. A WorkQueue with N workers is created
2. Each row is written to the WorkQueue input socket
3. Workers process rows in forked processes via `Process.fork`
4. Results flow through the output socket back to the main process
5. The `callback` receives results from workers

## Indexing

**`TSV.index` / `TSV.range_index` / `TSV.pos_index`** (`lib/scout/tsv/index.rb`):
- **Point index** — Standard key→value index using the full key as lookup
  key. Built via `Persist.tsv` with the appropriate engine (usually BDB).
- **Range index** — For numeric ranges. Uses FixWidthTable for O(1) range
  queries. Requires a `range` flag in the engine options.
- **Position index** — For exact positions (a special case of range index).

Indexes are persisted using `Persist.tsv` with the `:engine` option
specifying the storage backend. The default for general use is "HDB"
(Hash Database). For range queries, FixWidthTable is used.

## Identifier translation

**`TSV.change_id` / `TSV.change_key`** (`lib/scout/tsv/change_id.rb`):
Translates the key field of a TSV to a different identifier format. Uses
identifier files (TSV files that map between formats) to build a translation
index. The `attach` method is used under the hood.

**`TSV.translation_index`**:
Builds a persisted index for translating between identifier formats. Uses
the identifier files found in the data directory or specified explicitly.

## Attach / Join

**`TSV.attach`** (`lib/scout/tsv/attach.rb`):
Joins columns from one TSV into another based on a matching key. Key
features:
- `match_key` / `other_key` — specify matching columns (auto-detected if
  not specified)
- `fields` — which fields from `other` to add
- `insitu` — modify the source TSV in-place vs. creating a new one
- Uses the Transformer pattern for streaming join
- Auto-detects identifier files for format translation

## Serialization

**`TSVAdapter::SERIALIZER_ALIAS`** (`lib/scout/persist/tsv/serialize.rb`):
Maps TSV value types to serializer classes:

| Type | Serializer | Storage format |
|------|------------|----------------|
| `:single` | `StringSerializer` | Raw string with nil sentinel |
| `:list` | `StringArraySerializer` | Tab-separated |
| `:flat` | `StringArraySerializer` | Tab-separated |
| `:double` | `StringDoubleArraySerializer` | Tab-separated, pipe-sub-split |
| `:integer` | `IntegerSerializer` | 4-byte packed |
| `:float` | `FloatSerializer` |  hash_database.
| `:integer_array` | `IntegerArraySerializer` | 4-byte packed array with nil sentinel |
| `:float_array` | `FloatArraySerializer` | 8-byte packed array with nil sentinel |

Special serializers: `:marshal` (Marshal.dump), `:json` (JSON.dump),
`:marshal_tsv` (Marshal.dump of the whole TSV), `:tsv` (text serialization).

## Annotation persistence

The TSVAdapter (in `persist/tsv/adapter/base.rb`) automatically persists
TSV annotations alongside the data. The annotation hash is serialized with
Marshal and stored under the key `__annotation_hash__`. On load, the
adapter re-creates the TSV with its original annotations (type, key_field,
fields, namespace, etc.).

The `self.extended(base)` hook handles two paths:
- **TSV already built**: saves annotation hash
- **New persistence**: loads annotation hash and calls `TSV.setup` to
  rebuild the annotation state

## Design observations

1. **Streaming-first architecture** — The traverse/Transformer/Dumper triad
   is the backbone of all data operations. Every transformation can be
   executed as a streaming pipeline without materializing intermediate
   results.

2. **Polymorphic dispatch on source type** — `Open.traverse` handles
   TSV, Hash, Array, IO, Step, String, and Parser sources with a single
   API. This makes it the universal data-processing entry point.

3. **Annotation-based metadata** — TSV metadata (type, fields, key_field,
   namespace) is stored as annotations, not as a separate schema. This
   means metadata travels with the object across operations.

4. **Persistence is transparent** — All operations can be persisted via
   `Persist.tsv` with engine selection. The TSVAdapter protocol handles
   serialization and annotation persistence automatically.

5. **NamedArray integration** — When traversing with `unnamed: false`,
   values are wrapped in NamedArray objects so blocks can access fields by
   name instead of position. This is both ergonomic and self-documenting.

## Warnings

- The `:double` type uses `|` as sub-separator; data containing `|` in values
  will be incorrectly split. This is a fundamental format limitation.
- Serialization of floats uses `-999.999` as nil sentinel; data containing
  this exact value will be misinterpreted as nil.
- The `into: :stream` path creates a pipe and runs traversal in a thread;
  errors in the background thread may not propagate immediately. The
  ConcurrentStream protocol handles this with `abort` callbacks.
- When using WorkQueue parallelization, forked workers cannot share in-memory
  state. All data must be serializable through the IPC sockets.
