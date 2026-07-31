# Caching Data

This document explains how to persist computed results to avoid redundant
computation. It covers choosing the right persistence engine, managing
cache invalidation, and using persistence within workflows.

It is intended for workflow authors who process large datasets and need
reliable caching.

## What problem does this solve?

When you process large datasets, recomputing results on every run is
expensive. You need to cache results so that subsequent runs reuse them.
But caching introduces questions:

- What storage format is best for my data? (In-memory hash? A persistent database?
  database? Custom binary format?)
- How do I know if the cache is still valid?
- Where should cached data be stored?
- What if the data is too large for memory?

Scout-gear's persistence system handles all of these. It provides multiple
storage engines, automatic cache invalidation based on the source data,
and integration with the workflow system.

## When do I use it?

- When you process large TSV files and want to avoid re-parsing them on
  every run.
- When building indexes that are expensive to compute.
- When you want workflow results to be cached automatically.
- When you need range or position indexes for coordinate-based lookups.

## Core concepts

### Automatic persistence in workflows

Every workflow job result is persisted automatically. The result path is
derived from the job's inputs and dependency signatures, so:

- If you run the same job again, the cached result is returned.
- If inputs change, a new path is generated (new result).
- If you clean the job (`job.clean`), the result is recomputed.

You don't need to do anything special to get workflow caching — it's built
in.

### Explicit persistence with Persist

For data that isn't a workflow result, use the `Persist.persist` method:

```ruby
result = Persist.persist("data_identifier", :HDB, prefix: "MyIndex") do |filename|
  # This block only runs if the cache is invalid or doesn't exist
  expensive_computation
end
```

`Persist.persist` checks if a valid cache exists. If it does, the cached
result is loaded. If not, the block is executed, and the result is saved
to `filename`.

### Persistence for TSV

When opening a TSV, use the `persist: true` option to store it in a
database:

```ruby
tsv = TSV.open("large_file.tsv", persist: true, engine: :HDB)
```

First load populates the database; subsequent loads read from it directly,
skipping the parser.

## Choosing a persistence engine

Different engines suit different use cases:

| Code | Best for |
|------|----------|
| `:HDB` | General-purpose key-value storage, fast lookups (default) |
| `:BDB` | Range queries, ordered access on the key |
| `:tkrzw` | Modern alternative to the default engine |
| `:fwt` | Coordinate-based range queries (e.g., genomic positions) |
| `:pi` | Compact integer-to-integer indexes |
| `:sharder` | Splitting a large database across multiple files |

### When to use which engine

- **`:HDB`** is the default for most TSV data. It provides O(1) lookups
  and handles large datasets well.
- **`:BDB`** is for when you need ordered access or range queries on the
  key itself.
- **`:fwt`** is used for genomic coordinate lookups. It's built
  automatically by `TSV.range_index`.
- **`:sharder`** splits a large database into multiple files (shards) based
  on a shard function. Useful when a single database file would be too large.

## Cache invalidation

Cache invalidation is based on the source data and the persistence prefix.

### Prefix-based invalidation

Each persisted result has a prefix that identifies the operation:

```ruby
Persist.persist("my_data", :HDB, prefix: "Step1") { ... }
```

If the prefix changes, a new cache is created. This lets you version your
processing pipeline: changing the prefix forces recomputation.

### Source-based invalidation

For TSV persistence, the cache is invalidated when the source file changes:

```ruby
tsv = TSV.open("data.tsv", persist: true)
# If data.tsv is modified, the cache is rebuilt on next load
```

This uses file modification time and size to detect changes.

### Manual invalidation

Force recomputation by cleaning the cache:

```ruby
# Remove all persisted data for a workflow
job.clean

# Remove persisted TSV
FileUtils.rm_rf(Persist.persistence_path("my_data", :HDB, prefix: "MyIndex"))
```

## Persistence within TSV operations

Many TSV operations accept persistence options:

```ruby
# Persist the result of an index operation
index = TSV.index(tsv, target: "GeneName", persist: true)

# Persist the result of a range index
index = TSV.range_index(tsv, "start", "end", persist: true)

# Persist attach results
result = tsv.attach(other_tsv, persist: true)
```

## Common mistakes

- **Choosing the wrong engine**: If you need range queries, don't use
  `:HDB`. Use `:BDB` or `:fwt`. If your data is small, an in-memory hash is
  fine (no persistence needed).
- **Forgetting to persist indexes**: Building an index over a large file is
  expensive. Always use `persist: true` for indexes you'll reuse.
- **Stale caches after code changes**: If you change the processing logic
  inside a `Persist.persist` block, the old cache is still used. Change the
  prefix or clean the cache to force recomputation.
- **Using persistence for one-off computations**: If you're only computing
  something once, persistence adds overhead. Use it for data you'll reload
  repeatedly.
- **Not cleaning test caches**: During development, old cache files can
  accumulate in `var/`. Periodically clean with `rm -rf var/jobs/` and
  `rm -rf var/databases/` to start fresh.

## See also

- [scout-essentials: Caching Results](https://github.com/mikisvaz/scout-essentials/blob/main/doc/user/CachingResults.md)
- [scout-essentials: Producing Resources](https://github.com/mikisvaz/scout-essentials/blob/main/doc/user/ProducingResources.md)
- [Building Workflows](BuildingWorkflows.md)
- [Processing Tabular Data](ProcessingTabularData.md)
- [Cookbook](Cookbook.md)
