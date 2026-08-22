# Persistence Engines

This document describes the internal architecture of the persistence layer.

It is intended for framework contributors who need to understand the
storage engines, the TSVAdapter serialization chain, and how to add new
engines.

## Overview

The persistence layer provides multiple storage engines behind a unified
API. `Persist.persist` itself lives in
[scout-essentials](https://github.com/mikisvaz/scout-essentials) — it
resolves the cache path, takes a lock, checks cache validity, loads, or
runs the block. Scout-gear contributes the **engines** and the TSV
serialization chain on top of that machinery:

- `Persist.save_drivers[:tsv]` / `Persist.load_drivers[:tsv]`
  (`persist/tsv.rb:5-28`) teach essentials' `Persist.persist` to write
  and read TSV-shaped content.
- `Persist.open_database(path, write, serializer, type, options)`
  (`persist/tsv.rb:31-52`) dispatches to concrete engines.
- `Persist.tsv(id, options, engine:, persist_options:)` (`persist/tsv.rb:55`)
  is the convenience wrapper used by `TSV.open(..., persist: true)`.
- `Persist::TSVAdapter` (`persist/tsv/adapter.rb` + `adapter/`) bridges
  TSV objects and engines.

Where engine classes come from (`persist/engine.rb` requires):

- TokyoCabinet (`engine/tokyocabinet.rb`, via the `tokyocabinet` gem —
  `ScoutCabinet.open`) — HDB and BDB.
- FixWidthTable (`engine/fix_width_table.rb`).
- PackedIndex (`engine/packed_index.rb`).
- Sharder (`engine/sharder.rb`).
- Tkrzw (`engine/tkrzw.rb`, optional).

## Persist.persist

The core API (implemented in scout-essentials, used here):

```ruby
Persist.persist(identifier, engine, prefix: nil, **opts) do |filename|
  # Runs only if cache is invalid or missing
  expensive_computation
end
```

Flow:
1. Resolve the persistence path from `identifier`, `engine`, and `prefix`.
2. Check if the cache file exists and is valid.
3. If valid: open the database and return it.
4. If invalid or missing: run the block, passing the database filename.
5. The block writes to `filename` and returns the database object.

Engine-specific caveat: the `:HDB` **save driver** expects the block to
return an engine object (`ScoutCabinet`-like or something with a
`persistence_path`); returning a plain Hash fails to save and silently
re-runs on subsequent calls. Return an engine object or use `Persist.tsv`
for TSV content. Cache-hit detection here is also sensitive to the
`:dir` option — a relative custom `:dir` is not "located", so
cross-process reuse needs the default cache dir or an absolute `:path`.
Both behaviors are demonstrated in [Caching Data](../user/CachingData.md).

### Path resolution

The persistence path is derived from:
- The `identifier` (a string, a file path, or an object with
  `persistence_path`).
- The `prefix` (a versioning tag).
- The `engine` type (determines file extension).

This follows the scout-essentials
[path conventions](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/PathResolution.md).

## Storage engines

Each engine is a Ruby class (or set of classes) that implements a
key-value store with serialization. Engines implement the `TSVAdapter`
interface for TSV serialization, but can also be used standalone.

`Persist.open_database(path, write, serializer, engine, options)`
(`persist/tsv.rb:27-47`) recognizes exactly three engine *case arms*, all as
Strings: `'fwt'` and `'pki'`, plus an `else` branch that hands the engine name
to `Persist.open_tokyocabinet`. Inside `ScoutCabinet.open`
(`persist/engine/tokyocabinet.rb:25-27`) the names `"HDB"`/`:HDB` and
`"BDB"`/`:BDB` are normalized to TokyoCabinet classes, and a `":big"`
suffix (e.g. `"BDB:big"`) applies large/deflate tuning. **Any other name is
passed through as the database class and fails** (`NoMethodError: undefined
method 'new' for an instance of String`) — this includes `"tkrzw"`, which is
*not* reachable through `open_database` at all.

Two consequences worth knowing:

- `'fwt'` requires `value_size` and `range` in options; `'pki'` requires
  `pattern` (a `pack`-style mask array of Strings such as
  `%w(i i 23s f f f f f)`, see `test_packed_index.rb`) and accepts an optional
  `pos_function`. Missing options raise deep errors, not clean ones.
- Symbol engine names only work for `:HDB`/`:BDB`: the `case` in
  `open_database` matches Strings, so `:fwt` silently falls through to the
  TokyoCabinet branch and fails.

### TokyoCabinet Hash Database (HDB)

- **Code**: `"HDB"` (default in `Persist.tsv` and `TSV.index`)
- **Files**: `persist/engine/tokyocabinet.rb`, `persist/tsv.rb`
- **Best for**: General-purpose key-value storage, fast O(1) lookups.
- **Characteristics**: Hash-based, no ordering, handles large datasets
  well. Opened via `ScoutCabinet.open(path, write, "HDB")`.

### TokyoCabinet B-Tree Database (BDB)

- **Code**: `"BDB"`
- **Best for**: Range queries, ordered access on the key.
- **Characteristics**: B-tree, ordered keys, supports range queries.

### FixWidthTable (FWT)

- **Code**: `"fwt"`
- **Files**: `persist/engine/fix_width_table.rb`
- **Best for**: Coordinate-based range queries (e.g., genomic positions).
- **Characteristics**: Fixed-width records, sorted by position, binary
  search. Used by `TSV.range_index`. Opened with
  `Persist.open_fwt(path, value_size, range, serializer, update,
  in_memory)`; supports a custom `pos_function` via options
  (`persist/tsv.rb:35-40`).

### PackedIndex (PKI)

- **Code**: `"pki"`
- **Best for**: Compact integer-to-integer indexes.
- **Characteristics**: Very compact binary index built around `Array#pack`
  masks. Opened with `Persist.open_pki(path, write, pattern)`
  (`persist/tsv/adapter/packed_index.rb:85`), where `pattern` is a mask array
  of Strings such as `%w(i i 23s f f f f f)`; element codes come from
  `PackedIndex::ELEMS` (`i`→`l`/4, `I`→`q`/8, `f`→`f`/4, `F`→`d`/8) plus
  `"Ns"` fixed-width string and `"code:N"` forms. An optional block is the
  `pos_function`. Symbol masks (`[:md5, "4s"]`) are not supported and raise
  `NoMethodError`.

### Sharder

- **Files**: `persist/engine/sharder.rb`, `persist/tsv/adapter/sharder.rb`
- **Best for**: Splitting a large database into multiple shard files using a
  custom shard function.
- **Characteristics**: Wraps another engine (per-shard `db_type`), distributing
  keys across files under one directory. Not selectable through
  `Persist.open_database`; it is used by `Persist.tsv(...)` when
  `persist_options[:shard_function]` is given
  (`persist/tsv.rb:55-58`), which calls `Persist.open_sharder`
  (`tsv/adapter/sharder.rb:47`). Shard engines may themselves be `'pki'`,
  `'fwt'`, `'HDB'`, etc. (see `test_sharder.rb`).

### Tkrzw (optional, not wired into `open_database`)

- **Files**: `persist/engine/tkrzw.rb`, `persist/tsv/adapter/tkrzw.rb`
  (both `require 'tkrzw'`, an optional gem)
- **Status**: adapter code exists and registers `:tkh` save/load drivers, but
  neither file is required by `scout.rb`, `persist/engine.rb`, or
  `persist/tsv/adapter.rb`, and the engine name `'tkrzw'` is not recognized by
  `Persist.open_database` (it raises NoMethodError as described above). Treat
  it as dormant code pending an explicit require; do not document it as a
  selectable engine.

