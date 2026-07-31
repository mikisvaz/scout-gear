# Investigation: Persistence Engines and Concurrency

> **Non-normative.** This document is a working investigation with
> implementation details, code exploration notes, and hypotheses. Refer to
> `doc/developer/` for maintained architectural documentation.

## Overview

scout-gear extends the basic `Persist` module from scout-essentials with
specialized database engines for TSV data, and provides two concurrency
primitives: WorkQueue (multi-process parallelism) and Semaphore (POSIX
named semaphore synchronization).

The persistence stack:

```
Persist.tsv (scout-gear)
    ↓
Persist.open_database  (engine dispatch)
    ↓
Engine: TokyoCabinet | FixWidthTable | PackedIndex | Sharder
    ↓
TSVAdapter (annotation + serialization)
    ↓
Engine-native API (TC HDB/BDB, packed binary, etc.)
```

## Persistence engines

### Engine dispatch

`Persist.open_database(path, write, serializer, type, options)` is the
central dispatch function. It selects the engine based on `type`:

| `type` value | Engine | Use case |
|--------------|--------|----------|
| `"HDB"` (default) | TokyoCabinet HDB | General-purpose key-value (Hash Database) |
| `"BDB"` | TokyoCabinet BDB | Ordered key-value (B+ Tree) |
| `"fwt"` | FixWidthTable | Fixed-width value storage with range support |
| `"pki"` | PackedIndex | Compact positional index |
| `"sharder"` or block | Sharder | Sharded database across multiple files |

### TokyoCabinet (HDB / BDB)

**`ScoutCabinet`** module (`persist/engine/tokyocabinet.rb`):
- Wraps `TokyoCabinet::HDB` (hash database) or `TokyoCabinet::BDB` (B+ tree)
- `ScoutCabinet.open(path, write, class)` — opens the database, caches
  connections in `Persist::CONNECTIONS` for reuse
- Supports "big" mode: `HDB:big` enables `TLARGE | TDEFLATE` flags for
  large databases
- Adds read/write/close methods compatible with the TSVAdapter protocol

Key features:
- Connection caching in `Persist::CONNECTIONS[path]` — avoids re-opening
- `read`/`write` methods toggle between reader and writer modes
- `fingerprint` returns `"<class>:<path>"` for cache identity

### FixWidthTable

**`FixWidthTable`** (`persist/engine/fix_width_table.rb`):
- Fixed-width binary storage for values of a known size
- Each record is `value_size + 8` bytes (or `+ 16` with range support)
- Supports range queries: `get_range(start, end)` returns all entries with
  `start ≤ value ≤ end`
- In-memory mode: loads entire file into StringIO for fast random access
- Used for genomic coordinate indexing (e.g., position → gene mappings)

Record layout:
```
[value_size bytes: value] [8 bytes: key offset into key file] [8 bytes: end range (if range mode)]
```

### PackedIndex

**`PackedIndex`** (`persist/engine/packed_index.rb`):
- Ultra-compact positional index using binary packing
- Each entry is packed according to a "mask" (pack template string)
- Used when values have a uniform structure (e.g., integers, floats, fixed strings)
- Mask syntax: `"i"` = 4-byte int, `"I"` = 8-byte int, `"f"` = 4-byte float,
  `"F"` = 8-byte float, `"Ns"` = N-byte string

### Sharder

**`Sharder`** (`persist/engine/sharder.rb`):
- Distributes keys across multiple databases (shards)
- `shard_function` (block or proc) determines which shard a key goes to
- Each shard is a separate database file (`shard-<id>`)
- Supports `prefix`, `get_prefix`, and `range` operations that span shards
- Used for very large datasets that exceed single-database performance

## TSVAdapter pattern

### Architecture

The TSVAdapter is a module mixed into opened databases to make them behave
like TSV objects. It lives in `persist/tsv/adapter/` with engine-specific
files for each engine type:

```
TSVAdapter (base.rb)     — core: locking, annotation, serialization
├── TokyoCabinet adapter — wraps HDB/BDB
├── FixWidthTable adapter — wraps FWT
├── PackedIndex adapter   — wraps PackedIndex
├── Sharder adapter       — wraps Sharder
└── Tkrzw adapter         — wraps Tkrzw (optional)
```

### Annotation persistence

TSVAdapter automatically persists TSV annotations alongside data. The
annotation hash (type, key_field, fields, namespace, etc.) is serialized
with Marshal and stored under the special key `__annotation_hash__`.

The `self.extended(base)` hook:
- **TSV → database**: saves the annotation hash
- **Database → TSV**: loads the annotation hash and rebuilds the TSV
  annotation state via `TSV.setup`

### Serialization

Each TSV value type has a corresponding serializer class
(`persist/tsv/serialize.rb`):

| TSV type | Serializer | Nil sentinel |
|----------|------------|--------------|
| `:single` | `StringSerializer` | `'nil'` |
| `:list` | `StringArraySerializer` | `'nil'` |
| `:flat` | `StringArraySerializer` | `'nil' |
| `:double` | `StringDoubleArraySerializer` | `'nil'` |
| `:integer` | `IntegerSerializer` | N/A |
| `:float` | `FloatSerializer` | N/A |
| `:integer_array` | `IntegerArraySerializer` | `-999` |
| `:float_array` | `FloatArraySerializer` | `-999.999` |
| `:marshal` | Marshal | N/A |
| `:json` | JSON | N/A |

**Warnings about sentinels**:
- `StringSerializer::NIL_STR = 'nil'` — the literal string "nil" in data
  will be misinterpreted as nil.
- `IntegerArraySerializer::NIL_INT = -999` — integer value -999 will be nil.
- `FloatArraySerializer::NIL_FLOAT = -999.999` — float value -999.999 will be nil.

### Locking

TSVAdapter provides read/write locking via `Open.lock`:
- `read_lock` — shared read lock
- `write_lock` — exclusive write lock
- `lock` — exclusive lock on the entire database

Lock files are stored in `tmp/tsv_locks/` by default.

### The `Persist.tsv` function

`Persist.tsv(id, options, engine:, persist_options:)` is the user-facing
entry point. It:
1. Determines the engine type (default HDB)
2. If `shard_function` is provided, uses Sharder
3. Calls `Persist.persist` with the appropriate engine
4. Inside the persist block, `yield(database)` lets the caller populate
   the database
5. Returns the persisted TSV (with TSVAdapter mixed in)

## Concurrency: WorkQueue

### Architecture

WorkQueue provides multi-process parallelism using `Process.fork` + IPC
sockets. It is scout-gear's primary parallelism mechanism for data
processing.

```
WorkQueue
├── @input (WorkQueue::Socket)   — input for workers
├── @output (WorkQueue::Socket)  — output from workers
├── @workers (Array<Worker>)     — forked worker processes
└── @reader (Thread)             — reads worker output
```

### Worker lifecycle

Each Worker is a forked process (`work_queue/worker.rb`):
1. `Process.fork` creates a child process
2. Child sets up signal handlers (SIGABRT → exit, SIGINT → exit)
3. Child loops reading from input socket: `while obj = input.read`
4. On each input object, calls the worker block: `block.call(obj)`
5. Writes result to output socket: `output.write(res)`
6. `DoneProcessing` is a sentinel: workers exit on receipt

**DoneProcessing**: A sentinel object sent to shut down a worker. When a
worker reads `DoneProcessing`, it writes it to output and exits.

**WorkerException**: If a worker raises an exception, it wraps it in
`WorkerException` and sends it to output, then exits with status 246.

### Socket IPC

**`WorkQueue::Socket`** (`work_queue/socket.rb`):
- Wraps a UNIX socket pair for IPC between parent and forked workers
- Objects are serialized via Marshal for transmission
- `write(obj)` — marshal + write
- `read` — read + unmarshal

### Reader thread

The parent process runs a reader thread that:
1. Reads from `@output` socket
2. For `DoneProcessing`: marks the worker as done
3. For `WorkerException`: re-raises the exception in the parent
4. For regular results: calls the callback (if provided)
5. Continues until all workers are done

### WorkQueue API

| Method | Purpose |
|--------|---------|
| `WorkQueue.new(workers, &block)` | Create queue with N workers |
| `add_worker(&block)` | Add a worker |
| `process(&callback)` | Start all workers + reader thread |
| `<<` (input) | Enqueue work item |
| `add_input(obj)` | Enqueue (alias) |
| `ignore_output` | Disable output collection |
| `remove_worker(pid)` | Remove a worker |

### Design observations

1. **Fork-based parallelism** — WorkQueue uses `Process.fork`, which means
   workers share memory via copy-on-write at fork time but cannot share
   mutable state afterward. All communication is via IPC sockets.

2. **Marshal serialization** — All objects passing through the sockets must
   be Marshal-serializable. This rules out closures capturing non-serializable
   objects, file handles (mostly), and some Ruby objects.

   **WorkQueue must be passed into the worker block** as a parameter, not
   captured in a closure, because the closure is marshaled to the forked
   process.

3. **Background thread output collection** — The reader thread decouples
   result collection from work distribution. This prevents the main process
   from blocking if workers produce results faster than the callback can
   process them.

3. **DoneProcessing as control flow** — Using a sentinel object for shutdown
   is elegant and avoids separate control channels.

4. **Exception propagation** — `WorkerException` wraps exceptions and sends
   them to the parent, which re-raises. This preserves error visibility in
   parallel processing.

## Concurrency: Semaphore

### Architecture

**`ScoutSemaphore`** (`semaphore.rb`) implements POSIX named semaphores
using RubyInline (embedded C code). It provides cross-process
synchronization for limiting concurrent access to resources.

### API

| Method | Purpose |
|--------|---------|
| `ScoutSemaphore.create_semaphore(name, value)` | Create named semaphore with initial value |
| `ScoutSemaphore.wait_semaphore(name)` | Decrement (P operation); blocks if value ≤ 0 |
| `ScoutSemaphore.try_wait_semaphore(name, timeout)` | Try to wait with timeout |
| `ScoutSemaphore.post_semaphore(name)` | Increment (V operation) |
| `ScourSemaphore.delete_semaphore(name)` | Remove named semaphore |

### Use in Workflow

Semaphores are used by the Workflow engine to limit concurrent execution
of steps. When a Step runs with a semaphore, it:
1. Creates (if needed) and waits on the semaphore before execution
2. Runs the task block
3. Posts to the semaphore after completion

This is configured via the `:semaphore` task option:

```ruby
task :heavy_compute => :tsv do
  # ...
end.semaphore = 4  # Limit to 4 concurrent executions
```

## Relationship to scout-essentials

The following concepts are from scout-essentials and are documented there:

- **`Persist.persist`** — The core persist/caching function with locking
- **`Persist.memory`** — In-memory caching with closure semantics
- **`Open.lock`** — File-based locking primitive
- **`ConcurrentStream`** — The streaming protocol with callbacks
- **`TmpFile`** — Temporary file management

scout-gear adds:
- Database engines (TokyoCabinet, FixWidthTable, PackedIndex, Sharder)
- The TSVAdapter pattern (annotation + serialization)
- WorkQueue and Semaphore

## Warnings

- **Sentinel collisions**: The nil sentinels in serializers (`'nil'`,
  `-999`, `-999.999`) can collide with real data values. Users should be
  aware of these edge cases.
- **Fork limitations**: WorkQueue workers cannot share mutable state. All
  data must pass through IPC sockets via Marshal serialization. Large
  objects incur significant serialization overhead.
- **TokyoCabinet connection caching**: `Persist::CONNECTIONS` caches open
  database connections by path. If multiple processes open the same path
  with different modes, the cached connection may be reused incorrectly.
- **Semaphore requires RubyInline**: The C compiler must be available at
  runtime for `RubyInline`. If the compiler is missing, semaphore
  synchronization silently fails (with a warning).
- **PackedIndex requires uniform structure**: The mask is fixed at creation
  time. Changing the data structure requires rebuilding the index.
- **Sharder shard_function must be deterministic**: The same key must always
  map to the same shard. Non-deterministic functions will lose data.
