# Concurrency Model

This document describes the internal architecture of the concurrency
primitives: WorkQueue and Semaphore.

It is intended for framework contributors who need to understand
multi-process parallelism in scout-gear.

## Overview

Scout-gear uses **fork-based parallelism** instead of threading for CPU-
intensive work. This avoids Ruby's Global Interpreter Lock (GIL) and gives
each worker an independent memory space. The WorkQueue system manages the
process pool and inter-process communication (IPC).

Synchronization between processes is provided by Semaphore, which uses
file-based locking with C extensions.

## WorkQueue

The WorkQueue is the primary concurrency abstraction. It manages a pool of
forked worker processes and distributes work items to them.

### Key files

- `lib/scout/work_queue.rb`
- `lib/scout/work_queue/worker.rb`
- `lib/scout/work_queue/socket_management.rb`

### Architecture

```
Main process
├── add_inputs(collection)     ← feed work items
├── process { |item| ... }     ← define worker block
├── callback { |result| ... }  ← define result handler
│
├── Worker 1 (fork) ←── IPC socket ──→ Main
├── Worker 2 (fork) ←── IPC socket ──→ Main
├── Worker N (fork) ←── IPC socket ──→ Main
```

1. The main process calls `WorkQueue.new(num_workers: N)`.
2. `add_inputs` queues work items (from an array or stream).
3. `process` defines the worker block.
4. `run` forks N workers.
5. Each worker reads items from the input socket, applies the block, and
   writes results to the output socket.
6. The main process reads results from the output socket and invokes the
   callback.

### IPC model

Communication between main and workers uses Unix sockets:

- **Input socket**: Main → workers (work items).
- **Output socket**: Workers → main (results).

Items are serialized via Marshal. This means the work items and the
results must be Marshal-compatible (no file handles, IO objects, Procs,
etc.).

### Streaming inputs

WorkQueue can read inputs from a stream (e.g., a ConcurrentStream) instead
of a fixed array. This allows processing of very large datasets without
loading all items into memory.

The input stream is consumed lazily by the main process, which forwards
items to workers as they become available.

### Lifecycle

```
new → add_inputs → process → callback → run → (workers fork) → join → done
```

- `new`: Create the queue object. No workers forked yet.
- `add_inputs`: Queue work items. Can be called multiple times.
- `process`: Define the worker block. Called once.
- `callback`: Define the result handler. Called once.
- `run`: Fork workers, process all inputs, collect results, join all
  workers. This is the main entry point.
- Workers exit when the input socket is closed (EOF).

### Error handling

If a worker raises an exception, the error is serialized and sent to the
main process via the output socket. The main process re-raises it.

If the main process dies, workers detect the broken socket and exit. If a
worker dies, the main process detects the broken socket and raises an
error.

## TSV traverse integration

The most common use of WorkQueue is through `TSV.traverse` with `cpus:`:

```ruby
tsv.traverse(:key, into: :tsv, cpus: 4) do |key, values|
  [key, expensive_compute(values)]
end
```

This creates a WorkQueue with 4 workers, feeds TSV rows as inputs, and
collects results into a TSV.

### Traverse integration details

1. The main process reads TSV rows from the source.
2. Rows are Marshal-serialized and sent to workers via IPC.
3. Workers deserialize, apply the block, and send back results.
4. The main process collects results into the `into:` target.
5. When the source is exhausted, the input socket is closed.
6. Workers exit on EOF, and the output socket is closed.
7. The `into:` target is finalized (e.g., a Dumper closes its pipe).

### Deadlock avoidance

The traverse integration uses streaming to avoid deadlocks:
- The input and output sockets are independent.
- The main process reads from the output socket while writing to the
  input socket.
- If the output buffer fills up, the main process blocks on output, but
  workers continue to drain the input.
- This is deadlock-safe as long as the block doesn't write to the same
  pipe it reads from.

## Semaphore

The Semaphore provides inter-process synchronization. It's used when
multiple processes need to access a shared resource (like a database or
file).

### Key files

- `lib/scout/semaphore.rb`

### Architecture

Semaphore uses file-based locking with C extensions (via RubyInline):

1. A lock file is created for each named resource.
2. `Semaphore.sync("resource") { ... }` acquires the lock, executes the
   block, and releases the lock.
3. Between acquire and release, other processes calling `Semaphore.sync`
   with the same resource name block until the lock is released.

### C extension

The C extension uses `flock` or `fcntl` for efficient, OS-level locking.
The C code is compiled at runtime via RubyInline, with the compiled code
cached in `~/.scout/tmp`.

### Fallback behavior

If the C compiler is not available (RubyInline can't compile), Semaphore
operations become **no-ops**. This means `Semaphore.sync` does NOT block.
This is a known limitation — ensure the C toolchain is available in
production environments.

### Use cases

- Protecting database writes when multiple WorkQueue workers share a
  database.
- Serializing file updates across processes.
- Coordinating access to shared resources in parallel traverse.

## Known issues

- **Marshal limitations**: Work items, worker blocks, and results must be
  Marshal-serializable. Procs with closures, IO objects, and Thread objects
  are not serializable.
- **Memory duplication**: Forked workers get a copy of the parent's memory
  (copy-on-write). For very large datasets, this can be significant.
- **Semaphore no-op fallback**: If C extensions can't compile, Semaphore
  silently becomes a no-op. This can lead to race conditions.
- **Socket cleanup**: If a process exits abnormally, sockets may not be
  cleaned up, leading to resource leaks.
- **WorkQueue not thread-safe**: WorkQueue is designed for multi-process
  use, not multi-threaded use within a single process.

## See also

- [Architecture](Architecture.md)
- [TSV Internals](TSVInternals.md)
- [Research: Persistence and Concurrency Analysis](../../research/persistence-concurrency-analysis.md)
- [scout-essentials: Streaming Model](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/StreamingModel.md)
