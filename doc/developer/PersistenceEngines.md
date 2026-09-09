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
return an annotated TSV or an engine object (`ScoutCabinet`-like, something
with a `persistence_path`); returning a plain `Hash` raises
`NoMethodError: undefined method 'annotate' for an instance of Hash` at save
time (`persist/tsv/adapter/tokyocabinet.rb`). Return a TSV/engine object or
use `Persist.tsv` for TSV content. Cache-hit detection here is also sensitive to the
`:dir` option — a relative custom `:dir` is not "located", so
cross-process reuse needs the default cache dir or an absolute `:path`.
Both behaviors are demonstrated in [Caching Data](../user/CachingData.md).

### Path resolution

The persistence path is derived from:
- The `identifier` (a string, a file path, or an object with
  `persistence_path`).
- The `prefix` (a versioning tag).
- The `engine` type (determines file extension).

**The engine type is *not* part of the cache identity.**
`Persist.persistence_path("probe_id_1", "HDB")`,
`...("probe_id_1", "BDB")` and `...("probe_id_1", "fwt")` all yield the
same path: cache identity is the identifier plus any `:other`-namespaced
options (which are digest-suffixed into the path), never the engine
string. Switching engines therefore does **not** create a new cache
entry; to invalidate an engine choice, bump the identifier or a prefix /
`:other` option.

The same rule makes the block body irrelevant to identity: two
`Persist.tsv` calls with the same identifier and different blocks resolve
to the same path, the second does not run its block, and it serves the
data written by the first.

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

FixWidthTable is **not** a TSVAdapter: it has no `key_field`/`fields`
metadata and no `keys`/`each` enumeration. Its query surface is `[]`,
`range`, `overlaps`, `get_range`, plus the lifecycle methods
`read`/`write`/`close`, `size`, and `persistence_path`. `[]` accepts an
Integer, a `Range`, or an **Array `[start, end]`** of positions; a String
position such as `'120-180'` is *not* parsed (it reaches the
`get_range`/`get_point` else-branch with the String used as both start and
end) and should never be passed. Use `TSV.range_index`, which builds a
correctly typed table for you.

### PackedIndex (PKI)

- **Code**: `"pki"`
- **Best for**: Compact integer-to-integer indexes.
- **Characteristics**: Very compact binary index built around `Array#pack`
  masks. Opened with `Persist.open_pki(path, write, pattern)`
  (`persist/tsv/adapter/packed_index.rb:85`), where `pattern` is a mask array
  of Strings such as `%w(i i 23s f f f f f)`; element codes come from
  `PackedIndex::ELEMS` (`i`→`l`/4, `I`→`q`/8, `f`→`f`/4, `F`→`d`/8) plus
  `"Ns"` fixed-width string and `"code:N"` forms. An optional block is the
  `pos_function`.

The mask grammar fails loudly rather than cleanly:

- Symbol masks (`[:md5, "4s"]`) are not supported and raise `NoMethodError`.
- Unknown codes and bare `'l'`/`'x'` are not rejected at parse time: they
  fall into the `code:N` split arm, produce an `item_size` below 3, and
  raise `ArgumentError: negative argument` from `initialize` (the nil
  sentinel string is built as `"NIL" + ("-" * (item_size - 3))`).
- `nil` as the pattern raises `NoMethodError` on `each`.
- **No `:pki` load driver is registered** (only `:HDB`, `:BDB`, `:fwt` and
  `:tsv`), so `Persist.load(path, :pki)` raises
  `RuntimeError: Persist does not know :pki` (scout-essentials'
  `Persist.deserialize` fallback) instead of reopening the index. Reopen a
  PackedIndex with `Persist.open_pki(path, write, pattern)` — where `pattern`
  may be `nil` for a read: the mask is read back from the 8-byte header the
  writer stores (`mask_length, item_size`, then the mask itself), so the
  pattern does not need to be repeated. The `pos_function` **does** need to
  be passed again (it is not persisted); reopening without it and then
  indexing by a String key fails with
  `TypeError: no implicit conversion of Integer into String` inside
  `get_position`. `Persist.persist(id, "pki")` round-trips correctly because
  the same block reopens it.

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

A sharder directory is not self-describing: it holds `shard-*` files plus a
`metadata` file, but nothing persists the shard function. Reopened with
`Persist.open_sharder(path, write, db_type)` and no block or
`:shard_function`, the object has `shard_function == nil` and any `[]`
raises `NoMethodError: undefined method 'call' for nil`. Supply the shard
function again — through `Persist.tsv`'s
`persist_options[:shard_function]`, or explicitly with
`Sharder#shard_function=`.

### Tkrzw (optional, not wired into `open_database`)

- **Files**: `persist/engine/tkrzw.rb`, `persist/tsv/adapter/tkrzw.rb`
  (both `require 'tkrzw'`, an optional gem)
- **Status**: adapter code exists and registers `:tkh` save/load drivers, but
  neither file is required by `scout.rb`, `persist/engine.rb`, or
  `persist/tsv/adapter.rb`, and the engine name `'tkrzw'` is not recognized by
  `Persist.open_database` (it raises NoMethodError as described above). Treat
  it as dormant code pending an explicit require; do not document it as a
  selectable engine.

## Load-time availability and silent degradation

`persist/engine/tokyocabinet.rb` probes for the `tokyocabinet` gem with a
plain `begin/rescue` around `require` at load time and, on failure, only
emits `Log.warn "The Tokyocabinet gem could not be loaded: TSV persistence
may not work"`. Nothing else changes: `Persist.open_database` still
dispatches to `Persist.open_tokyocabinet`, and the failure surfaces later,
as a `NameError`/`NoMethodError` on the missing constant at the point of
use. Engine availability is therefore a **load-time, best-effort** check —
plan for it, and do not rely on an early failure: the HDB/BDB engines
degrade silently until first use.

## Engine lifetime: `close` is advisory

`close` is best-effort cleanup, not a guarantee of state:

- **TokyoCabinet**: `close` sets `@closed = true`, `@writable = false` and
  closes the native handle, but the object **stays in
  `Persist::CONNECTIONS`**, which is never invalidated on close. A
  subsequent open of the same path (including
  `ScoutCabinet.open`/`Persist.open_database`) returns the *closed* object
  rather than re-reading from disk. That object is **not inert**:
  TokyoCabinet object-level writes keep flowing to disk through it (the
  Ruby binding re-opens lazily), so `db["k2"] = ...` after `close` still
  lands in the file. What you lose is a *fresh read* of the path — the
  cached object serves its own view of the database, so for a guaranteed
  fresh read within the same process call
  `Persist::CONNECTIONS.delete(path)` before reopening.
- **Sharder**: `close` marks `@closed` and delegates to each shard's own
  `close`; the same connection-cache caveat applies to the per-shard
  engines.
- **FixWidthTable**: the data is on disk after `close` and reloads fine
  (`Persist.load(path, :fwt)` — the `:fwt` load driver *is* registered).

Treat `close` as releasing a resource you are done with, not as a
synchronization point.
