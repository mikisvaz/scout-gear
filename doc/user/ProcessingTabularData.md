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

A TSV carries metadata: key field name, field names, namespace, cast, and
serializer. Operations preserve this metadata, so pipelines stay
self-describing (verified: reopening a persisted `:list` TSV gives
`a => ["1"]`, P031).

### Opening a file

```ruby
tsv = TSV.open("data.tsv", type: :list, sep: "\t")
```

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

With `persist: true`, the parsed TSV is stored in a database keyed by the
source path; re-`open` calls reuse it and the block does not run again
(probe P031: `re-open block runs: 0`). The type is preserved across
persistence (P031).

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

`tsv.traverse` (the instance method) yields rows to the block. For
parallel/streaming control use the module method `TSV.traverse` (below).

### Streaming collection with `into:`

`TSV.traverse(obj, into: target, ...)` collects block results into the
target (tsv/open.rb:36-30):

```ruby
result = {}
TSV.traverse tsv, into: result do |key, values|
  [key, values.map { |v| v.to_i * 2 }]
end
```

The `into:` target is an **object**, not a symbol:

| Target | Result |
|--------|--------|
| `Hash` / `TSV` | Merged by key |
| `Array` / `Set` | Appended |
| `TSV::Dumper` | Written as rows (streaming) |
| `IO` / `StringIO` | Written as lines |
| `nil` | Nothing collected; block runs for effect |

(`:tsv` / `:dumper` / `:array` symbols are **not** accepted — passing one
raises, as P031f first attempt showed. That's scout-essentials-era
shorthand that gear does not implement.)

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
are read; ordering is per-worker, not global. See
[Running Parallel Work](RunningParallelWork.md).

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
flips the test. It builds a fresh TSV carrying the same metadata.

There is **no `tsv.reject`** — use `select(..., true)` to invert. For very
large tables there is also the on-disk `filter` machinery
(tsv/util/filter.rb) used by the KnowledgeBase.

## Restructuring

```ruby
# Select columns (reorder.rb)
subset = tsv.slice(["Expression"])

# Change the key column, merging values by default
by_expression = tsv.reorder("Expression")

# Add columns from another TSV
merged = tsv.attach(other_tsv, fields: ["NewColumn"])
```

- `slice(fields)` keeps only the named fields.
- `reorder(key_field, fields: nil, merge: true, ...)` re-keys the table;
  when several rows share a new key, values are merged unless
  `merge: false`.
- `unzip`/`melt` split or reshape tables (tsv/util/unzip.rb, melt.rb).

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
becomes simply the target format name.

Mechanics, all in `tsv/change_id/translate.rb`:

- `TSV.translation_path(files, source, target)` (line 20) picks the chain
  of files: a single file containing both formats, else two files sharing
  a field, else three; `nil` when no path exists.
- `TSV.translation_index(files, source, target)` (line 49) builds and
  persists (`HDB` engine) a lookup TSV from source to target, attaching
  the files of the chain in sequence. The data TSV itself may participate
  in the chain.
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
