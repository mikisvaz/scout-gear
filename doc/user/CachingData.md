# Caching Data

This document explains how to persist computed results to avoid redundant
computation: choosing a persistence engine, controlling cache
invalidation, and using persistence inside workflows.

It is intended for workflow authors who process large datasets and need
reliable caching.

## What problem does this solve?

When you process large datasets, recomputing results on every run is
expensive. You want to cache results so that subsequent runs reuse them.
That raises questions:

- What storage format fits my data? (in-memory hash, key-value database,
  custom binary format)
- How do I know whether a cache is still valid?
- Where is cached data stored?
- What if the data is too large for memory?

Scout-gear's persistence layer answers these by combining the generic
`Persist` machinery from the scout-essentials dependency with a set of
storage engines implemented in this repository.

## Where persistence lives (ecosystem split)

- **scout-essentials** (dependency) defines the core `Persist.persist`
  mechanism: path resolution, the `:update`/`:check` invalidation
  controls, `Persist.memory` in-process caching, and the `save_drivers` /
  `load_drivers` registries.
- **scout-gear** (this repository) adds the heavy storage **engines**
  (`lib/scout/persist/engine/`) and the TSV-to-engine integration
  (`lib/scout/persist/tsv.rb`, `TSVAdapter`) that lets whole TSV objects
  live inside a database.

If a claim below is about `Persist.persist` itself, its authoritative
description lives in the scout-essentials documentation.

## When do I use it?

- When you parse large TSV files and want to skip re-parsing.
- When you build expensive indexes.
- When you want workflow results cached automatically.
- When you need range or position indexes for coordinate-based lookups.

## Core concepts

### Automatic persistence in workflows

Every workflow job result is persisted automatically. The result path is
derived from the job's inputs and dependency signatures:

- Running the same job again returns the cached result.
- Changed inputs generate a new path (a new result).
- `job.clean` removes the result so it is recomputed.

You do not need to do anything special to get workflow caching — it is
built in. (See [Building Workflows](BuildingWorkflows.md).)

### Explicit persistence with Persist

For data that is not a workflow result, use `Persist.persist`:

```ruby
result = Persist.persist("data_identifier", :HDB) do |filename|
  # Runs only when the cache is missing or :update / :check demand it
  expensive_computation
end
```

`Persist.persist` (implemented in scout-essentials) resolves `filename`
under the persistence directory, checks whether a valid database is
already there, and either loads it or runs the block to build it. When
the block receives `filename`, the result is the engine object opened on
that path (this is what `Persist.tsv` does).

### TSV persistence

To persist a TSV, use `Persist.tsv` (or `Persist.persist_tsv`, which is
its option-parsing wrapper):

```ruby
db = Persist.tsv("my_table", engine: :HDB) do |data|
  TSV.traverse("large_file.tsv") do |key, values|
    data[key] = values
  end
end
```

The block receives the opened database (a `TSVAdapter`), which behaves
like a TSV: it supports `[]`, `keys`, `through`, field and type
metadata, and persistence annotations. Options that the database needs —
notably `serializer:` — go into `persist_options`, not the top-level
`options` hash: `Persist.tsv` accepts only `id`, `options`, `engine:`
and `persist_options:` as keywords, so a top-level `serializer:` raises
`unknown keyword`. Use it like this:

```ruby
db = Persist.tsv("my_table", {}, engine: "HDB",
                 persist_options: { serializer: :list }) do |data|
  ...
end
```

The serializer itself is chosen through the
`TSVAdapter::SERIALIZER_ALIAS` table (`single`/`string`,
`list`/`flat`, `double`, `clean`, `integer`, `float`,
`integer_array`, `float_array`, `strict_integer_array`,
`strict_float_array`, `binary`, `marshal`, `json`, `tsv`,
`marshal_tsv`). A default serializer is only attached when the extended
object is already a `TSV`; a bare `Persist.open_database(path, true)`
result has `serializer == nil` and `[]=` fails with
`no implicit conversion of Array into String` if you then assign Ruby
structures to it as if it were a TSV. Populate such a database through
`Persist.tsv`, `TSV.open(source, data: db, ...)`, or
`TSV.setup(db, ...)` + `extend TSVAdapter`.

Opening a TSV **from** a database file uses the same drivers:

```ruby
tsv = Persist.load("var/databases/my_table", :HDB)   # TokyoCabinet database path
```

`Persist.load(path, :HDB)` returns the annotated database object with
its TSV metadata and typed values intact.

## Engines implemented here

Engines live in `lib/scout/persist/engine/` and are opened through
`Persist.open_database(path, write, serializer, engine, options)`
(`lib/scout/persist/tsv.rb:27`). The dispatch is narrower than the file list
suggests:

- `"HDB"` (default; `:HDB` also accepted) and `"BDB"`/`:BDB` open TokyoCabinet
  databases; a `":big"` suffix (e.g. `"BDB:big"`) tunes them with
  `TLARGE|TDEFLATE`.
- `"fwt"` (String) opens a FixWidthTable — it needs `value_size` and `range`
  options; `TSV.range_index` supplies them for you.
- `"pki"` (String) opens a PackedIndex — it needs a `pattern` mask array such
  as `%w(i i 23s f f f f f)`.
- **Anything else raises** (`NoMethodError: undefined method 'new' for an
  instance of String`), including `"tkrzw"` and the Symbol `:fwt` (the case
  arms match Strings only).

Engine availability is detected at load time and degrades silently:
`persist/engine/tokyocabinet.rb` wraps `require 'tokyocabinet'` in a
rescue that only logs a warning when the gem is missing, and the failure
surfaces later as a `NameError`/`NoMethodError` at the point of use
rather than at startup.

### Choosing an engine

- **`"HDB"`** is the default (`Persist.tsv` defaults `engine: :HDB`).
  O(1) key lookups, good general choice.
- **`"BDB"`** when you need ordered key access or range scans over keys.
- **`"fwt"`** for genomic-coordinate lookups; `TSV.range_index` builds it
  for you.
- **`"pki"`** for compact integer-position indexes.
- **Sharding** is not an engine name: `Persist.tsv` builds a Sharder
  automatically when you pass `persist_options[:shard_function]`
  (`persist/tsv.rb:55-58`), wrapping per-shard engines such as `'pki'` or
  `'HDB'`. The shard function is **not** stored in the database, so a
  later `Persist.tsv` for the same identifier must pass it again.
- Tkrzw adapter code exists (`engine/tkrzw.rb`) but is not loaded by the
  framework and cannot be selected through `open_database`; see
  [Persistence Engines](../developer/PersistenceEngines.md).

## Cache invalidation

`Persist.persist` decides whether to rebuild the block result using the
persistence options (`:update`, `:check` — defined in scout-essentials),
plus how the data was saved.

### Changing the identifier (versioning)

Cache identity is the `id` (the first argument) combined with
`:prefix`-style options and any other `:other`-namespaced options, which
are digest-suffixed into the path. Change the identifier (or bump the
prefix) to force a rebuild when your processing code changes:

```ruby
Persist.persist("my_data:v2", :HDB) { ... }   # new cache entry
```

Two things that are *not* part of cache identity:

- **Code changes.** The cached value is keyed by identifier, not by the
  block body: two `Persist.tsv` calls with the same identifier and
  completely different blocks resolve to the same path, the second does
  not run its block, and it serves the data written by the first.
- **The engine.** `persistence_path` is the same for `"HDB"`, `"BDB"`
  and `"fwt"` on a given identifier; switching engines does not create a
  new cache entry.

### Source-based invalidation

Data-flow helpers that read from files (for example TSV index helpers)
pass the source file as the identifier or include it in the cache
options, so a changed source produces a different cache identity.
Inspect each helper's implementation for exactly what it includes.

### Manual invalidation

- `job.clean` for workflow results.
- Delete the database directory for a `Persist.persist`/`Persist.tsv`
  identifier (under the persistence directory).
- `Persist::CONNECTIONS` caches open databases per path and is never
  invalidated on `close`; deleting files while a process holds a
  connection affects only later opens. Note that a cached *closed* object
  is still returned by later opens and still accepts writes that reach the
  file (TokyoCabinet re-opens lazily) — what you do not get is a fresh
  read of data written through another handle. For a guaranteed fresh
  read of the same path in the same process, drop the connection first:
  `Persist::CONNECTIONS.delete(path)`.

`close` in general is best-effort cleanup, not a flush guarantee — see
[Persistence Engines](../developer/PersistenceEngines.md) for the
per-engine details.

## Common mistakes

- **Choosing the wrong engine**: range queries need `:BDB` or `:fwt`,
  not `:HDB`.
- **Forgetting to persist indexes**: index construction over large files
  is expensive; persist indexes you will reuse.
- **Stale caches after code changes**: caches are keyed by identifier,
  not by code. Bump the identifier/prefix or delete the database.
- **Expecting persistence to make results immutable**: engines open in
  write mode by default; treat the returned object as a live database.
- **Assuming an engine is available**: the TokyoCabinet gem is probed at
  load time with only a logged warning on failure; a missing gem fails
  at first use, not at startup.
- **Passing a database path to `TSV.open`**: a bare `TSV.open(db_path)`
  parses the binary file as text and returns a near-empty plain `Hash`.
  Use `Persist.load(db_path, :HDB)`, or `TSV.open(source, persist: true)`
  on the *source* file whose persisted database exists.

## See also

- [Processing Tabular Data](ProcessingTabularData.md) — `persist: true`
  in TSV operations.
- [Persistence Engines](../developer/PersistenceEngines.md) — engine
  internals.
- [Building Workflows](BuildingWorkflows.md) — automatic job caching.
- [Cookbook](Cookbook.md)
