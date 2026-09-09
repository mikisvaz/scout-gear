# Processing Tabular Data

This document explains scout-gear's TSV layer: opening existing data,
creating tables, transforming, filtering, restructuring, joining, and
persisting results.

It is intended for workflow authors and analysts processing structured data.

> **Ownership note.** The TSV data structure itself — parser, dumper,
> persist integration, `IndiferentHash`, `Log`, `Path` — comes from the
> **scout-essentials** dependency. scout-gear layers on top of it the
> persistence *engines* (TokyoCabinet/ KyotoCabinet adapters), the
> entity/annotation integration, and the workflow machinery that produces
> TSVs. This page documents the TSV behavior as you actually get it from
> `require 'scout'` in this repo, but deep internals (lock semantics,
> stream plumbing) live in scout-essentials and are documented there.

## What problem does this solve?

Tabular data — keyed rows with typed columns — is the most common format in
bioinformatics and data analysis. You need to:

- Parse TSV/CSV efficiently, with typed columns.
- Process rows without loading everything into memory.
- Join tables, filter rows, translate identifiers, restructure columns.
- Persist intermediate results so recomputation is cheap.

## Core concepts

### TSV

A TSV is a Hash-like object where each key maps to one or more values. The
**value type** determines the shape of the values:

| Value type | Structure | Example value for one key |
|------------|-----------|---------------------------|
| `:single` | One value per key | `"42"` |
| `:list` | Array of values per key | `["42", "yes"]` |
| `:flat` | Flat array, no per-field nesting | `["a", "b", "c"]` |
| `:double` | Array of arrays | `[["a"], ["b"]]` |

Selecting fields or the key **by name requires a header**: on a
headerless source, `key: "ID"` raises
`RuntimeError: Non-numeric fields specified, but no field names
available`, while `key: 0, fields: [1]` (0-based positions over the
whole line, key included) works. With a header, both forms are accepted
(`key:` also takes a Symbol). When the requested key field *equals* a
header field name, the key column is dropped from `fields:` unless you
also list it in `fields:`. A key-field name that is absent from the
header fails late and bare, with
`TypeError: no implicit conversion from nil to integer` from
`Parser#traverse` — pass an existing field name or a position.

A TSV carries metadata: key field name, field names, namespace, cast, and
serializer. Operations preserve this metadata, so pipelines stay
self-describing (verified: reopening a persisted `:list` TSV gives
`a => ["1"]`, P031). For `:list`/`:double` TSVs the row returned by `[]`
and by `each` is a `NamedArray` — an `Array` annotated with `fields` and
the `key` — so `row["V1"]` and `row.first` both work; `:single` rows are
plain Strings, `:flat` rows plain arrays, and `to_hash` gives an
unannotated plain Hash. `tsv.with_unnamed { }` strips the annotation
inside the block and restores it afterwards (`unnamed: true` at open is
the persistent form).

### Opening a file

```ruby
tsv = TSV.open("data.tsv", type: :list, sep: "\t")
```

Paths also carry a convenience method: `path.tsv` (`tsv/path.rb`) opens
the file as a TSV and forwards its options, so
`Path.new("data.tsv").tsv(type: :list)` is equivalent to the call above.

Common options (tsv.rb:75-131; scout-essentials parser):

| Option | Purpose |
|--------|---------|
| `type:` | Value type (`:single`, `:list`, `:flat`, `:double`) |
| `sep:` | Field separator (default `\t`) |
| `key_field:` | Which column is the key (name or index) |
| `fields:` | Which columns to load (names or indices) |
| `cast:` | Convert values (`:to_i`, `:to_f`) |
| `select:` | Filter rows by field values |
| `grep:` / `invert_grep:` | Pre-parse line filtering |
| `persist:` | Persist parsed data (see [Caching Data](CachingData.md)) |
| `engine:` | Persistence engine (`"HDB"` default; `"BDB"`, `"fwt"`, `"pki"` — see below) |
| `sep2:` | Sub-value separator for `:double` values (default `"|"`) |
| `key:` | Alias for `key_field:`; accepts a name, index, or `Symbol` |
| `header_hash:` | Header marker (`'#'` default; any custom marker string; `false`/`'none'`/`'~'` disables headers) |

With `persist: true`, the parsed TSV is stored in a database keyed by the
source path; re-`open` calls reuse it and the block does not run again
(probe P031: `re-open block runs: 0`). The type is preserved across
persistence (P031). An explicit `persist:` path also serves the *old*
content after the source file changes — the cache is keyed on the path,
not the contents, so bump or delete the cache (or use `persist: true`
with the default fingerprint) when the source moves. Options passed to
`open` override `#:` directives embedded in the file header.

`TSV.open` on an existing `TSV` does **not** hand back the same object:
it re-materializes a new Hash-backed TSV with the same keys/fields and
metadata. There is no `TSV.get` alias in scout-gear.

#### Header directives — a pitfall

Files may declare their own type/separator with `#:` comment headers, e.g.
`#: :type=:double`. **Placement matters** (P031b/P031d):

- `#::type=:double` (or `#: :type=:double` alone) works — the directive is
  applied and the following header line defines fields.
- `#: :sep=/t#:type=:double` **breaks parsing**: the whole string is
  treated as one directive value, so `sep` becomes `"/t#:type=...double"`,
  the field line is consumed as data, and you get key `"ID\tVal"` with no
  fields. Keep each directive on its own `#:` line, and put `:sep=` either
  alone or last.

(This is because the directive string is split on `#` before `key=value`
parsing — see `IndiferentHash.string2hash` in scout-essentials and
`TSV::Parser.parse_header`, parser.rb:257-300.)

Directive tails are tolerant: `#: :type=:double` and `#:type=:double`
parse alike (the leading `:` on the key is optional), and a value-less
directive such as `#: :compact` yields `{compact: true}`. A separate
`:sep2=` directive (or the `sep2:` open option) sets the sub-value
separator (quote the value if it is a bare `:`, e.g. `#: :sep2=':'` —
an unquoted `:` is read back as a Symbol). Object-level options —
including `entity_options` — do **not** survive a dump/reload cycle:
the writer emits only Scalar-valued options into the `#:` preamble, and
the reader does not restore them.

### CSV sources

`TSV.csv(obj, type: :list, headers: true, ...)` (`tsv/csv.rb:4`) parses
comma-separated input (a `Path`, filename, remote URL, or `StringIO`)
with Ruby's `CSV`. Keys and field names come from the first row when
`headers:` is true; with `headers: false` keys are `row-0`, `row-1`, …
and there are no field names. `key_field:`/`fields:` selection forces an
intermediate `:double` rebuild with `merge: true`, then converts back to
the requested type. There is no `TSV::CSV` constant — the entry point is
the module method only.

### Creating a TSV from scratch

```ruby
data = {
  "gene1" => ["100", "up"],
  "gene2" => ["200", "down"],
}

TSV.setup(data, type: :list, key_field: "Gene", fields: ["Expression", "Change"])
```

`TSV.setup` also accepts a single DSL string that carries the same
information: `"Key~F1,F2#:type=:list"` sets the key field (`~`),
the field list (`,`), and the `#:` options, in one argument.

## Transforming data

### Traverse

`traverse` iterates over rows with optional field selection, type
conversion, and filtering (traverse.rb):

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

`tsv.traverse` (the instance method) yields rows to the block and returns
the `[key_field, fields]` header pair of the traversal, not data. For
parallel/streaming control use the module method `TSV.traverse` (below).

A `type:` passed to the instance method **coerces** the values to the
requested shape for the duration of the traversal: traversing a `:list`
TSV with `type: :double` yields `[["1"], ["2"]]` — the shape follows the
*requested* type, not the stored one. Selecting fields by *name* in the
same call still requires a header (`Non-numeric fields specified`).

The two APIs differ in their `unnamed` default: the instance method
yields `NamedArray`-annotated values (so `values["V1"]` works inside the
block), while the class method defaults `unnamed: true` for raw stream
sources — a TSV instance passed to `TSV.traverse` keeps its own setting.
A 3-arity block receives `nil` as the third element in both; field names
are never yielded. Multi-key rows (`:double` keys joined by `|`) cannot
be selected by *named* fields — named selection requires a header, so use
positions or accept the default join.

### Streaming collection with `into:`

`TSV.traverse(obj, into: target, ...)` collects block results into the
target (`tsv/open.rb:36`); note the module method defaults
`unnamed: true`, so values arrive as plain arrays unless you pass
`unnamed: false` (or traverse a TSV whose own `unnamed` is false):

```ruby
result = {}
TSV.traverse tsv, into: result do |key, values|
  [key, values.map { |v| v.to_i * 2 }]
end
```

The `into:` target is an **object**, not a symbol:

| Target | Result |
|--------|--------|
| `Hash` / `TSV` | Merged by key (`key => value`; a `:double` TSV uses `zip_new`, other TSV types are last-wins on duplicate keys) |
| `Array` / `Set` | Whole `[key, values]` rows appended |
| `TSV::Dumper` | Written as rows (streaming) |
| `IO` / `StringIO` | One `puts` per result |
| `Path` | Written with `Open.write` |
| `:stream` | An `Open.pipe`; the call returns the read end |
| `nil` | Block results are discarded |

Whatever the target, **`TSV.traverse` returns the `into:` object itself**
(`into || res`), so the call hands back the very object you passed in.
With no `into:` the block runs for its side effects only and block
results are **discarded**: a TSV or `Parser` source returns the header
pair `[key_field, fields]` of the traversal (`traverse.rb:164`), a
stream/StringIO source returns the empty parsed container. Collect into
an explicit target if you need the results.

A symbol such as `into: :tsv` is *not* a target: it falls through the
`traverse_add` dispatch untouched, nothing is collected, and the symbol
comes back unchanged (`open.rb:12-34`). Pass a concrete object instead.

One block result can become several rows: returning
`MultipleResult.setup([...])` from the block fans the array out into one
`traverse_add` call per element (`MultipleResult` is a module, so the
idiom is `res.extend MultipleResult`), while a plain array return stays a
single `[key, values]` row — which is also what an `into:` `Array` or
`Set` collects, one pair per block result.

### Parallel processing

Use `cpus:` with `TSV.traverse` to fork workers (open.rb:92):

```ruby
result = {}
TSV.traverse tsv, cpus: 4, into: result do |key, values|
  [key, expensive_compute(values)]
end
```

This creates a `WorkQueue` with N workers, streams rows through it, and
merges results into `result` (probe P031f). Rows are distributed as they
are read; ordering is per-worker, not global, so do not rely on the order
in which an `into:` target is filled or a `callback:` fires — trials with
the same input flip between ordered and unordered arrival, so only the
final contents are deterministic. An exception raised in the block aborts
the queue and re-raises at the call site with its message preserved.
See [Running Parallel Work](RunningParallelWork.md).

## Filtering

```ruby
# Keep only rows whose key or values are in the collection (select.rb)
filtered = tsv.select(["gene1"])

# Regex over key/values
filtered = tsv.select(/up$/)

# Block predicate over a field
up = tsv.select("Change") do |change|
  change == "up"
end

# Invert any of the above
not_up = tsv.select("Change", true) do |change|
  change == "up"
end
```

`select(method = nil, invert = false, &block)` keeps rows whose key or
value intersects `method` when it is an Array/Set/Range, matches when it is
a Regexp, or for which the (field-aware) block returns true; `invert:`
flips the test. It builds a fresh TSV carrying the same metadata. A Hash
`method` is also accepted and is treated as a `field => values`
specification.

There is **no `tsv.reject`** — use `select(..., true)` to invert. For very
large tables there is also the on-disk `filter` machinery
(tsv/util/filter.rb) used by the KnowledgeBase. To use it, call
`tsv.filter` **first** (it extends the TSV with `Filtered` and returns the
receiver); then `add_filter(match, value)` selects rows, with `match`
either `:key` or the string `"field:<name>"` — anything else raises
`RuntimeError: Unknown match: <match>` (there is no bare `field:`/name
form). Filters intersect: each `add_filter` narrows the previous set and
`pop_filter` restores the one before it. The filter set is consulted by
`filtered_keys`/`filtered_each`/`filtered_collect` and by normal `[]`
access; a persistence directory can be supplied per filter or via
`filter(dir)`.

## Restructuring

```ruby
# Select columns (reorder.rb)
subset = tsv.slice(["Expression"])

# Change the key column, merging values by default
by_expression = tsv.reorder("Expression")

# Add columns from another TSV
merged = tsv.attach(other_tsv, fields: ["NewColumn"])
```

- `slice(fields)` keeps only the named fields and returns a **new** TSV
  (it is `reorder :key, fields`, so the receiver is untouched).
- `reorder(key_field, fields: nil, merge: true, ...)` re-keys the table;
  fields become `[old key field, ...rest]`. When several rows share a new
  key, values are merged unless `merge: false` — for `:list` rows the
  **last** row wins either way, so preserve all duplicates by merging into
  a `:double` type first.
- `unzip(field, sep:, delete: true)` promotes a field into the key: new
  keys are `"<old key>:<field value>"` joined by `sep`, the key field
  name becomes `"<KeyField>:<Field>"`, and the unzipped column is
  dropped (`delete: false` keeps it). On a `Parser`/filename source,
  `TSV.unzip` returns a **materialized** TSV, not a `Transformer`.
- `melt_columns(value_field, column_field)` reshapes wide to long: one
  row per (key, column), keys become `"<key>:<column index>"` and fields
  become `[key_field, value_field, column_field]`.
- `sort_by(field)` returns an **Array of `[key, values]` pairs** ordered
  by the field, not a new TSV.
- `process(field) { |v| ... }` rewrites one field's values **in place**
  (the receiver is returned); the block's return value replaces the
  field value.

## Joining tables — `attach`

`attach` (tsv/attach.rb:45) joins columns from `other` into `self`:

```ruby
result = tsv.attach(protein_tsv, fields: ["Protein"])
result = tsv.attach(protein_tsv, fields: ["Protein"],
                    match_key: "GeneID", other_key: "EnsemblID")
```

- If `match_key`/`other_key` are not given, they are **auto-detected**
  (attach.rb:3-42): a shared field name, then a key-field match, then
  identifier files, falling back to the source key. Auto-detection is
  heuristic — pass explicit keys in pipelines (this heuristic is the
  subject of improvement item A1 in [Improvements](../Improvements.md)).
- If the two tables have no direct match, `identifiers:` files are used to
  build a translation index (attach.rb:81-87).
- `one2one:` (default true) discards ambiguous joins unless disabled;
  `complete:` adds an empty row for unmatched keys.
- On a materialized TSV the receiver is **mutated and returned**: columns
  are appended to `tsv.fields`, and rows whose key has no match get a
  `nil` in the attached columns. `complete: true` goes further and adds
  rows for keys that exist only in the attached table (source columns
  `nil`).
- When the source is a `Parser` or a filename, pass `target: :stream` to
  get a `TSV::Dumper`-backed TSV whose `to_s` renders the merged table
  (`TSV.open(stream)` materializes it) instead of a materialized TSV; the
  column-selection keyword is `fields:` — there is no `field:`. Matching
  on a named column of the receiver uses `match_key:` (the value of that
  column), with `other_key:` for the other side.

## Translating identifiers — `translate`, `change_id`

An **identifier file** is an ordinary TSV whose header field names are the
identifier formats it maps between — `#Associated Gene Name,Ensembl Gene
ID` maps between those two formats, in either direction. A single file can
serve any pair of its columns; the pair is chosen at translation time.

`tsv.translate(field, format)` (tsv/change_id/translate.rb:116) rewrites
one column (or the key) into the target format:

```ruby
# Identifier file: #Name,Alias,ID
identifiers = TSV.open("test/data/person/identifiers")

marriages = TSV.open("test/data/person/marriages", identifiers: identifiers)
# key_field "Husband (ID)", fields ["Wife (ID)", "Date"]

names = marriages.translate("Husband (ID)", "Husband (Name)")
# key_field "Husband (Name)", values translated 001 -> Miguel
```

A parenthesized header keeps its label and swaps its format:
`Husband (ID)` becomes `Husband (Name)`; a plain header such as `ID`
becomes simply the target format name. Format names must match column
names literally — a format that names no column of the main TSV and no
column of an identifier file raises `Could not traverse identifier path
from X to Y` (the message dumps the available fields). Rows without a
translation are **not dropped**: they survive with an empty-string key
and their values intact, which silently merges several untranslated rows
under `""` — filter them out if that matters.

Mechanics, all in `tsv/change_id/translate.rb`:

- `TSV.translation_path(files, source, target)` (line 20) picks the chain
  of files: a single file containing both formats, else two files sharing
  a field, else three. Column order inside a file does not matter —
  `#Entrez,Ensembl` works as well as `#Ensembl,Entrez`. When no chain
  exists the error is a `RuntimeError` quoting the source TSV's summary.
- `TSV.translation_index(files, source, target)` (line 49) builds and
  persists (`HDB` engine) a lookup TSV from source to target, attaching
  the files of the chain in sequence. The data TSV itself may participate
  in the chain. The index is written under
  `~/.scout/var/cache/persistence` with a
  `Translation_index:<source>-><target>_(N_files_-_md5)` basename (the
  md5 covers the file paths), so a later call with the same files hits
  the cache; many-to-one mappings collapse to one target value.
- `TSV.translate` rewrites the header (see above) and applies the index
  row by row; `stream: true` returns a `TSV::Transformer` instead of a
  materialized TSV.

`change_id(tsv, source_id, new_id)` (tsv/change_id.rb:33) is a thin
wrapper that swaps one field via `attach`; `change_key` (line 5) re-keys
the table via the identifier files when the new key field is not already
present. Files are located from the `identifiers:` option, both tables'
own fields, and an `identifiers` entry next to the file's directory; see
[Working With Entities](WorkingWithEntities.md) for entity-declared files.

## Indexing

`TSV.index` (tsv/index.rb:40) builds a lookup TSV mapping one field's
values to another (or to keys). It underlies identifier translation and
KnowledgeBase joins, and supports `persist:` like any TSV operation.

The `fields:` option defaults to `:all`, so **every** column of the source
is indexed, not just the `target:` column — an index built with
`target: "GeneName"` answers for the values of every other column too.
Pass `fields: ["GeneName"]` to restrict it. When a value occurs in
several rows the first row seen wins — under both `order:` settings the
first row in traversal order wins, `order:` only changes how the source
is read (a `:double` traverse with `uniq.first` vs a flat traverse that
skips values already present); the index `key_field` is the
comma-joined list of indexed source column names and its single field is
the target column name. The default `target:` is `:key`, so
`tsv.index` with no arguments is the identity-style mapping in which
every column value maps to the row key it appeared in; `tsv.index` on
an instance delegates to the class method. `TSV.range_index(tsv, "Start", "End")` and
`TSV.pos_index(tsv, "Pos")` build a `FixWidthTable` for
coordinate-range and position lookups. A persisted index (`persist:
true`) comes back as a `TokyoCabinet::HDB` database rather than a Hash;
`index[coord]` on a range index returns the list of keys whose interval
covers the coordinate.

## Streaming out

Two helpers turn a TSV back into a stream without materializing an
intermediate copy:

- `tsv.dumper_stream(unmerge: false, keys: nil, preamble: true)` emits
  the serialized form; `unmerge: true` (only for `:double`) splits each
  `|`-joined sub-value into its own row, `keys:` restricts to a subset,
  and `preamble: false` drops the `#:` directive line. `tsv.to_s` is
  this stream read to a String, and `tsv.stream` is an alias of
  `dumper_stream`.
- `TSV.paste_streams([s1, s2])` merges several keyed streams into one by
  key (aligning on the first stream's key order); `TSV.collapse_stream(s)`
  folds **consecutive** duplicate keys into `|`-joined values (sort or
  group first — scattered duplicates are not merged), and it accepts raw
  text streams as well as `dumper_stream`s.

## Persistence and caching

Pass `persist: true` (or a path) plus an `engine:` to cache parsed or
intermediate data:

```ruby
tsv = TSV.open("data.tsv", type: :double, persist: true, engine: :HDB)
```

- Engine names reach `Persist.open_database`: `"HDB"`/`:HDB` (default) and
  `"BDB"`/`:BDB` open TokyoCabinet databases; `"fwt"` and `"pki"` (Strings
  only) open FixWidthTable/PackedIndex. Any other name raises. See
  [Caching Data](CachingData.md) and
  [Persistence Engines](../developer/PersistenceEngines.md).
- Separately, `serializer:` picks a value serialization:
  `TSVAdapter::SERIALIZER_ALIAS` defines `:single`, `:list`, `:flat`,
  `:double`, `:clean`, `:integer`, `:float`, `:integer_array`,
  `:float_array`, `:strict_integer_array`, `:strict_float_array`,
  `:marshal`, `:json`, `:string`, `:binary`, `:tsv`, `:marshal_tsv`
  (`persist/tsv/serialize.rb:99`).
- Automatic cache files land under `var/cache/persistence` (project-local)
  or `~/.scout/var/cache/persistence` depending on `Scout.var` resolution,
  named after the source, e.g. `TSV:data·d.tsv:<md5>` — nested paths are
  flattened with `·` (probe P031e).
- Reuse is keyed by source path and options, so changing `type:` changes
  the cache entry; `:update` forces regeneration (CachingData).

## See also

- [Running Parallel Work](RunningParallelWork.md) — `cpus:`, WorkQueue.
- [Caching Data](CachingData.md) — persistence usage.
- [Persistence Engines](../developer/PersistenceEngines.md) — engine list.
- [Working With Entities](WorkingWithEntities.md) — annotations, `unnamed:`.
