# Concurrency Model

This document describes the internal architecture of the concurrency
primitives: WorkQueue and ScoutSemaphore.

It is intended for framework contributors who need to understand
multi-process parallelism in scout-gear.

## Overview

Scout-gear uses **fork-based parallelism** instead of threading for CPU-
intensive work. This avoids Ruby's Global VM Lock and gives each worker
an independent memory space. The WorkQueue system manages the process
pool and inter-process communication (IPC).

Synchronization between processes is provided by ScoutSemaphore, which
uses named POSIX semaphores (C extension built with RubyInline).

## WorkQueue

The WorkQueue is the primary concurrency abstraction. It manages a pool
of forked worker processes and distributes work items to them.

### Key files

- `lib/scout/work_queue.rb`
- `lib/scout/work_queue/socket.rb`
- `lib/scout/work_queue/worker.rb`
- `lib/scout/work_queue/exceptions.rb`

### Architecture

```
Main process
│
├── WorkQueue.new(N, &block)  ← create queue, N workers, worker block
├── process { |result| ... }  ← start workers + result reader thread
├── write(item)               ← send one work item
├── close                     ← signal no more input
└── join                      ← wait for workers, return results
│
├── Worker 1 (fork) ←── sockets ──→ Main
├── Worker 2 (fork) ←── sockets ──→ Main
└── Worker N (fork) ←── sockets ──→ Main
```

The actual API (`work_queue.rb`):

```ruby
wq = WorkQueue.new(4) do |item|   # initialize(workers, &block)
  process_item(item)
end
wq.process { |result| collect(result) }  # forks workers, starts reader
wq.write(item)                         # one item at a time
wq.close                               # no more input
results = wq.join                      # wait + collect
```

Key methods and lines: `initialize` (`work_queue.rb:15`), `add_worker`
(:30), `process` (:64), `write` (:144), `abort` (:154), `close` (:166),
`clean` (:177), `join` (:183).

1. `WorkQueue.new(workers, &block)` creates two `WorkQueue::Socket`s
   (input and output) and `workers` Worker objects; no processes yet.
2. `process(&callback)` forks all workers with the worker block and
   starts a reader thread that pulls results from the output socket and
   calls the callback.
3. `write(obj)` sends a work item through the input socket.
4. `close` sends a `DoneProcessing` sentinel to remove one worker, and
   the reader thread tracks done workers; workers exit when the input
   socket closes (EOF) or they receive `DoneProcessing`.
5. `join` waits for all workers and returns collected results.
6. `add_worker`/`remove_one_worker`/`remove_worker(pid)` resize the pool
   dynamically.

### IPC model

Communication between main and workers uses socket pairs wrapped by
`WorkQueue::Socket` (`work_queue/socket.rb`):

- **Input socket**: Main → workers (work items).
- **Output socket**: Workers → main (results, `DoneProcessing`
  sentinel).

Items are serialized via Marshal. This means the work items and the
results must be Marshal-compatible (no file handles, IO objects, Procs,
etc.).

### Error handling

- `abort(exception)` sends the exception to workers and shuts the queue
  down (`work_queue.rb:154`).
- If a worker raises, the exception is marshalled back and re-raised in
  the main process (see `work_queue/exceptions.rb`).
- If the main process dies, workers detect the broken socket and exit;
  if a worker dies, the reader thread raises.

### Relation to TSV.traverse

The engine core does not use WorkQueue. Its main consumer is the
class-level `TSV.traverse(obj, cpus: N)` (`tsv/open.rb:36-145`), which
builds a WorkQueue when `cpus > 1` (`tsv/open.rb:92`):

```ruby
TSV.traverse(tsv, cpus: 4, into: {}) do |key, values|
  [key, expensive_compute(values)]
end
```

Note this is the **class method** `TSV.traverse`; the instance method
`tsv.traverse(...)` has no `cpus:`/`into:` keyword.

### Deadlock avoidance

The traverse integration streams:
- Input and output sockets are independent.
- The main process writes to input while the reader thread drains the
  output socket concurrently.
- If the output fills up, the reader thread continues draining while
  workers process.
- This is deadlock-safe as long as the block doesn't write to the pipe
  it reads from.

## ScoutSemaphore

ScoutSemaphore provides inter-process synchronization with named POSIX
semaphores. It is used when multiple processes must access a shared
resource (like a database or file) with bounded concurrency.

### Key files

- `lib/scout/semaphore.rb`

### Architecture

The module builds a small C extension with RubyInline implementing
`sem_open`/`sem_wait`/`sem_post`/`sem_unlink` over named semaphores.
Semaphores are visible as `/dev/shm/sem.<name>` (`exists?`,
`semaphore.rb:117`).

The Ruby API (all module methods, `semaphore.rb`):

| Method | Line | Purpose |
|--------|------|---------|
| `ensure_semaphore_name(file)` | :108 | Normalize to a valid POSIX name (`/x_y_z`) |
| `exists?(name)` | :117 | Check `/dev/shm/sem.<name>` |
| `with_retry(**opts)` | :138 | Retry with exponential backoff + jitter on `RETRIABLE_ERRNOS` |
| `ensure_or_create(name, size)` | :164 | Create or open with a value |
| `create_semaphore(name, value)` | :209 | `sem_open(O_CREAT)` |
| `delete_semaphore(name)` | :219 | `sem_unlink` |
| `wait_semaphore(name)` | :227 | `sem_wait` (interrupt-aware) |
| `post_semaphore(name)` | :256 | `sem_post` |
| `synchronize(sem) { }` | :278 | wait, yield, post (raises on failure) |
| `with_semaphore(size, file)` | :307 | create, yield name, ensure delete |
| `fork_each_on_semaphore(elems, size, file)` | :335 | Run block per element with bounded forks |
| `thread_each_on_semaphore(elems, size)` | :349 | Same with threads |

### Synchronization pattern

```ruby
ScoutSemaphore.with_semaphore(4, "my_resource") do |name|
  # name is a valid POSIX semaphore name; processes started here can
  ScoutSemaphore.synchronize(name) { critical_section }
end
```

`with_semaphore` creates a semaphore of the given size, yields its name,
and deletes it in `ensure`. `synchronize` waits, runs the block, and
posts in `ensure` — failures to post **raise**, they are not swallowed
(`semaphore.rb:278-305`).

### Error semantics

- Failures to create/wait/post raise `SystemCallError` (they do not
  silently degrade).
- `SemaphoreInterrupted` (subclass of `TryAgain`) is raised when a wait
  is interrupted; it propagates rather than being retried blindly.
- `with_retry` retries only on the listed retriable errnos
  (`ENOENT`, `EIDRM`, `EAGAIN`, `EMFILE`, `ENFILE`, `EINTR`;
  `semaphore.rb:123-132`) with exponential backoff and jitter; fatal
  errnos (`EINVAL`, `EACCES`) raise immediately.

### Load-time behavior

If the `inline` (RubyInline) gem cannot be loaded, the module logs
"semaphore synchronization will not work" and **defines nothing**
(`semaphore.rb:1-8`). Unlike a silent no-op, any call to a ScoutSemaphore
method then fails with `NoMethodError` — the failure is loud, not silent.

### Use cases

- Bounding the number of concurrent processes around a shared resource.
- Serializing file or database updates across processes.

### Known issue

`fork_each_on_semaphore` (`semaphore.rb:335`) delegates to
`TSV.traverse(elems, :cpus => size, :into => Set.new)` and calls
`elems.annotate` — `Set` does not respond to `annotate`, and the method
raises `NoMethodError` for `Misc.fingerprint` in current probes (see
research probe P031f). Prefer `with_semaphore` + explicit forks/threads.

## Known issues

- **Marshal limitations**: Work items and results must be
  Marshal-serializable. Procs with closures, IO objects, and Thread
  objects are not serializable. (The worker *block* is not marshalled —
  workers are forked, so they inherit the block.)
- **Memory duplication**: Forked workers get a copy-on-write view of the
  parent's memory. For very large in-memory structures this can be
  significant.
- **WorkQueue is process-level**: it manages forked workers, not
  threads; `thread_each_on_semaphore` is the thread-based alternative.
- **Socket cleanup**: If a process exits abnormally, sockets may not be
  cleaned up, leaking file descriptors until GC.

## See also

- [Architecture](Architecture.md)
- [TSV Internals](TSVInternals.md)
- [Running Parallel Work](../user/RunningParallelWork.md)
- [scout-essentials: Streaming Model](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/StreamingModel.md)
