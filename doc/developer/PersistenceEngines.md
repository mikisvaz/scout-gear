# Persistence Engines

This document describes the internal architecture of the persistence layer.

It is intended for framework contributors who need to understand the
storage engines, the TSVAdapter serialization chain, and how to add new
engines.

## Overview

The persistence layer provides multiple storage engines behind a unified
API. The key entry point is `Persist.persist`, which checks for a valid
cache, loads it if present, or runs a block and stores the result.

Persistence builds on
[scout-essentials' persistence](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/PersistenceAndResources.md),
which provides the path conventions and file locking.

## Persist.persist

The core API:

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

### Path resolution

The persistence path is derived from:
- The `identifier` (can be a string, a file path, or a TSV object).
- The `prefix` (a versioning tag).
- The `engine` type (determines file extension).
- For TSV persistence, the source file's path and mtime.

This follows the scout-essentials
[path conventions](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/PathResolution.md).

## Storage engines

Each engine is a Ruby class (or set of classes) that implements a
key-value store with serialization. Engines implement the `TSVAdapter`
interface for TSV serialization, but can also be used standalone.

### TokyoCabinet Hash Database (HDB)

- **Code**: `:HDB`
- **Files**: `lib/scout/persist/tsv_adapter.rb` (TSVAdapter), `lib/scout/persist/tokyocabinet.rb`
- **Best for**: General-purpose key-value storage, fast O(1) lookups.
- **Characteristics**: Hash-based, no ordering, handles large datasets well.

### TokyoCabinet B-Tree Database (BDB)

- **Code**: `:BDB`
- **Best for**: Range queries, ordered access on the key.
- **Characteristics**: B-tree, ordered keys, supports range queries.

### Tkrzw

- **Code**: `:tkrzw`
- **Best for**: Modern alternative to TokyoCabinet with better performance
  in some scenarios.
- **Characteristics**: Successor to TokyoCabinet, mixed hybrid database.

### FixWidthTable (FWT)

- **Code**: `:fwt`
- **Files**: `lib/scout/persist/fix_width_table.rb`
- **Best for**: Coordinate-based range queries (e.g., genomic positions).
- **Characteristics**: Fixed-width records, sorted by position, binary
  search. Used by `TSV.range_index`.

### PackedIndex (PI)

- **Code**: `:pi`
- **Best for**: Compact integer-to-integer indexes.
- **Characteristics**: Very compact format for mapping integers to integers.

### Sharder

- **Code**: `:sharder`
- **Best for**: Splitting a large database into multiple files based on a
  shard function.
- **Characteristics**: Wraps another engine (e.g., HDB), distributing keys
  across multiple files to avoid single-file size limits.

## TSVAdapter serialization

The `TSVAdapter` is the serialization layer between TSV objects and
storage engines. It converts a TSV (an annotated Hash) into a format
suitable for storage and back.

### Serialization chain

```
TSV (annotated Hash)
       │
       ▼
TSVAdapter.open(filename, type)
       │
       ▼
Engine (HDB, BDB, etc.)
       │  write key => serialized_value
       │
       ▼
```

For each key-value pair in the TSV:
1. The value (which can be a scalar, array, or nested array depending on
   type) is serialized.
2. The serialized value is stored in the engine.

On read:
1. The engine returns the serialized values.
2. TSVAdapter deserializes them back into the correct Ruby types.
3. The TSV annotations (key_field, fields, type) are restored from a
   metadata header.

### Metadata persistence

TSVAdapter stores metadata (key_field, fields, type, namespace) in a
special key (typically the header line). On load, this metadata is
restored to the TSV annotation.

## Engine selection

The engine is selected via the `engine:` option (or the second argument to
`Persist.persist`). If no engine is specified, a default is chosen based on
the data type:

- TSV data → HDB (hash database)
- Range indexes → FixWidthTable
- Custom data → caller's choice

## Caching and invalidation

### Cache validity

Cache validity is determined by:

1. **File existence**: The cache file must exist.
2. **Source modification time**: For TSV persistence, the source file's
   mtime is stored. If the source is newer than the cache, the cache is
   invalid.
3. **Prefix**: Changing the prefix creates a new path (effectively
   invalidating the old cache).

### Concurrent access

Persistence uses scout-essentials'
[file locking](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/PersistenceAndResources.md)
to prevent concurrent writes to the same cache file. When a process is
writing to a cache, others wait for the lock.

## Extension points

### Adding a new engine

To add a new storage engine:

1. Create `lib/scout/persist/<engine_name>.rb`.
2. Implement the key-value interface: `[]`, `[]=` (or `write`), `read`,
   `open`, `close`.
3. Implement `TSVAdapter` compatibility (or wrap an existing adapter).
4. Register the engine in the engine dispatch table.

## Known issues

- TokyoCabinet and Tkrzw require native extensions. If not available, only
  in-memory (unpersisted) storage works.
- FixWidthTable is limited to fixed-width keys. Long keys may be truncated.
- The Sharder's shard function is hash-based, so data distribution may be
  uneven.
- Some engines don't support concurrent writes well; use file locking.

## See also

- [Architecture](Architecture.md)
- [TSV Internals](TSVInternals.md)
- [Research: Persistence and Concurrency Analysis](../../research/persistence-concurrency-analysis.md)
- [scout-essentials: Persistence and Resources](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/PersistenceAndResources.md)
- [scout-essentials: Path Resolution](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/PathResolution.md)
