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
4. `close` writes one `DoneProcessing` sentinel **per worker** (so every
   worker drains and exits); workers also exit on input EOF.
5. `join(clean = true)` joins the waiter and reader threads and then calls
   `clean` in its `ensure` — note the reader must be able to finish first,
   which is exactly what a bare `abort` does not guarantee (see below).
6. `add_worker`/`remove_one_worker`/`remove_worker(pid)` resize the pool
   dynamically.

The public API is exactly `process`/`write`/`close`/`join` plus
`abort`/`clean`; `add_worker`, `remove_one_worker`, `remove_worker(pid)` and
`ignore_ouput` also exist. There is **no `add_inputs` and no `run`** —
`process` *is* the fork-and-run step. (`callback` and `worker_proc` exist
only as attribute accessors over the stored blocks; `ignore_ouput` — typo
included — suppresses worker results.)

### IPC model

Communication between main and workers uses socket pairs wrapped by
`WorkQueue::Socket` (`work_queue/socket.rb`):

- **Input socket**: Main → workers (work items).
- **Output socket**: Workers → main (results, `DoneProcessing`
  sentinel).

Items travel in a compact 4-type framing rather than plain Marshal
(`Socket#dump`/`#load`, `work_queue/socket.rb:35-94`): every frame starts with
`[payload_size, type].pack('La')` (5 bytes), where the type tag selects the
encoding:

| Tag | Object | Encoding |
|---|---|---|
| `I` | `Integer` | the 4-byte size field carries the *value* itself |
| `N` | `nil` | 5 bytes total, no payload |
| `C` | `String` | raw bytes, never marshalled; restored with `force_encoding('UTF-8')` |
| `S` | anything else | a Marshal blob (arrays, hashes, symbols, annotated objects, exceptions) |

Consequences for work items and results: they must be
`Marshal`-compatible unless they are Integers or Strings (no file handles,
IO objects, Procs, etc. — a `Proc` item raises `TypeError` in the parent).
Two sharp edges:

- **Integers are truncated to signed 32-bit.** `dump(-1)` loads back as
  `4294967295` and `dump(2**40)` as `0`; the `I` frame uses `pack('l')`.
  Keep Integer work items/results inside the signed 32-bit range.
- `dump` clears `obj.concurrent_stream` on any object that responds to it
  before marshalling, so stream-carrying objects survive the trip by losing
  that one attribute.

### Error handling

- `abort` takes **no arguments** — the `abort(exception)` signature belongs
  to `Socket#abort` (`socket.rb:128`), not to the queue. `WorkQueue#abort`
  sends SIGABRT to every worker and posts the output write-semaphore plus
  the input read-semaphore once per worker to nudge blocked peers
  (`work_queue.rb:154-164`).
- A worker child traps `ABRT` and does `Kernel.exit! 246`
  (`Worker::EXIT_STATUS`), and the waiter thread explicitly whitelists that
  exit status; any other non-zero exit raises the generic
  `Exception "Worker <pid> ended with status <n>"` in the parent.
- If the main process dies, workers detect the broken socket and exit.
- A worker that raises sends the *inner* exception back (`WorkerException`,
  `work_queue/exceptions.rb`); the reader thread aborts the whole queue —
  killing the other workers too — and re-raises that inner exception, which
  surfaces from `join`.
- `DoneProcessing` derives from `Exception`, **not** `StandardError`
  (`work_queue/exceptions.rb:1`), so a bare `rescue` in a worker block does
  not swallow the shutdown sentinel. `WorkerException` (which does derive
  from `StandardError` via `ScoutException`) carries the inner exception and
  the worker pid back to the parent.

#### `abort` does not finish the teardown — `clean` does

`abort` kills the workers but does **not** close the parent's own write-end
of the output socket. The reader thread therefore never sees EOF and stays
blocked inside `Socket#load`; a bare `wq.join` after `wq.abort` hangs
**indefinitely**. Only closing that write-end (via `clean`, which closes
both ends and deletes the socket semaphores) lets the reader finish —
it then dies with `IOError "stream closed in another thread"` and `join`
returns.

This is why `TSV.traverse(cpus:)` pairs them: its `rescue` calls
`queue.abort` and its `ensure` calls `queue.clean`
(`tsv/open.rb:113-117`). When aborting a queue yourself, always
`abort` then `clean`:

```ruby
begin
  wq.process { |r| collect(r) }
  items.each { |i| wq.write i }
  wq.close
  wq.join
rescue Exception
  wq.abort
  raise
ensure
  wq.clean          # without this, the reader thread never terminates
end
```

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

Its teardown is `queue.join(false)` in the happy path with `queue.clean`
still in the `ensure` (`join`'s own `clean` is skipped so the `ensure`
owns it once, on both the success and the abort path).

### Deadlock avoidance

The traverse integration streams:
- Input and output sockets are independent.
- The main process writes to input while the reader thread drains the
  output socket concurrently.
- If the output fills up, the reader thread continues draining while
  workers process.
- This is deadlock-safe as long as the block doesn't write to the pipe
  it reads from.

There is no protocol-level backpressure: `Socket#dump` does a raw
`stream.write` loop with no timeout, so a write to a socket nobody is
reading blocks indefinitely (a ~200 KB payload with no reader blocks
`dump`; a reader thread keeps a 1 MB round-trip moving).

### Frame atomicity: every socket is two named semaphores

`Socket#initialize` creates `/dev/shm/sem.<random>.<pid>.in` and `...out`
(value 1 each); `push` wraps `dump` in `synchronize(@write_sem)` and `pop`
wraps `load` in `synchronize(@read_sem)`. These two permits are what keep
multiple forked children from interleaving frames on one pipe — a writer
holds the write semaphore, a reader the read semaphore. `Socket#clean`
closes both pipe ends *and* deletes both semaphores, and `WorkQueue#abort`
posts the output write-semaphore and the input read-semaphore once per
worker (`work_queue.rb:158-160`) to unblock a stuck peer. This is the
load-bearing reason `work_queue/socket.rb` requires `scout/semaphore` (and
therefore RubyInline).

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
`semaphore.rb:119`).

Loading the module needs **two** things, not one: RubyInline (missing it
logs "semaphore synchronization will not work" and leaves the module
without its C methods) *and* scout-essentials' exceptions — the class body
references `TryAgain` at load time, so on a scout-gear-only path
`require 'scout/semaphore'` fails with
`NameError: uninitialized constant ScoutSemaphore::TryAgain`.

The Ruby API (all module methods, `semaphore.rb`):

| Method | Line | Purpose |
|--------|------|---------|
| `ensure_semaphore_name(file)` | :110 | Normalize to a valid POSIX name (`/x_y_z`) |
| `exists?(name)` | :119 | Check `/dev/shm/sem.<name>` |
| `with_retry(**opts)` | :140 | Retry with exponential backoff + jitter on `RETRIABLE_ERRNOS` |
| `ensure_or_create(name, size)` | :166 | Create or open with a value |
| `create_semaphore(name, value)` | :211 | `sem_open(O_CREAT)` |
| `delete_semaphore(name)` | :221 | `sem_unlink` |
| `wait_semaphore(name)` | :229 | `sem_wait` (interrupt-aware) |
| `post_semaphore(name)` | :258 | `sem_post` |
| `synchronize(sem) { }` | :280 | wait, yield, post (raises on failure) |
| `with_semaphore(size, file)` | :309 | create, yield name, ensure delete |
| `fork_each_on_semaphore(elems, size, file)` | :337 | Run block per element with bounded forks |
| `thread_each_on_semaphore(elems, size)` | :351 | Same with threads |

Name normalization (`ensure_semaphore_name`) always prefixes `/`, collapses
leading slashes to one, and maps any remaining `/` to `_` — so
`tmp/x_y.lock` becomes `/tmp_x_y.lock` and lives on disk as
`/dev/shm/sem.tmp_x_y.lock`. Names are *not* namespaced per user or per
process; a stale name in `/dev/shm` is shared by every Scout process on the
host, and `wait`/`post` silently **recreate a missing semaphore with value
1** on `ENOENT`/`EIDRM` (`ensure_or_create`, `semaphore.rb:166`) rather than
failing. That recreation is what makes the queues resilient to a stray
`sem_unlink`, but it also means a typo in a semaphore name cannot be
detected at the call site.

Three behaviors that are easy to get wrong:

- **The auto-recreate value is 1, not the original size.** A process
  holding a permit in a semaphore that was meanwhile unlinked can be
  joined by a "new" permit, breaking the bound. To detect a stale name use
  `exists?`, never `wait` — `wait` recreates instead of failing.
- **`synchronize` releases the permit even when the block raises.** The
  `post` lives in an `ensure`; failures to post do raise (the code
  deliberately reverted an earlier swallow).
- **`thread_each_on_semaphore` swallows exceptions.** It rescues
  `Exception`, logs, kills the threads ("Ensuring threads are dead: N")
  and returns the array of (now dead) `Thread` objects rather than the
  block's results — callers get no signal that work was lost. Use it only
  for blocks that cannot fail, or read the results out of the returned
  threads yourself (`threads.map(&:value)` raises the swallowed error on
  the first failed element).

`with_semaphore(size)` deletes the semaphore on exit and only *warns* if
the delete fails — it never raises.

`synchronize(sem)` posts in its `ensure` block, so the permit is released
even when the guarded block raises — but a failed `post_semaphore` *is*
re-raised from that `ensure`. `SemaphoreInterrupted < TryAgain` signals an
EINTR wait; note the constant only resolves after `scout/exceptions` has
been loaded (`require 'scout'` alone is not enough).

### The bounded-map helpers are not equivalent

- `thread_each_on_semaphore(elems, size)` works: it spawns one thread per
  element, gated to `size` concurrent, joins them, and returns the array of
  `Thread` objects — results are in `thread.value` (see the exception
  swallowing note above before relying on them).
- **`fork_each_on_semaphore(elems, size)` is currently broken in this
  tree**: it calls `Misc.fingerprint` (`semaphore.rb:337`) to build a
  progress-bar title, and `Misc` has no `fingerprint` method
  (`Misc.digest` exists), so it raises
  `NoMethodError: undefined method 'fingerprint' for module Misc` on entry.
  The fingerprint API lives on `Log` (`Log.fingerprint`), so the fix is a
  one-line change; until then use `thread_each_on_semaphore` (mind its
  exception swallowing) or `TSV.traverse(elems, cpus: n)`.

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
(`semaphore.rb:280-306`).

### Error semantics

- Failures to create/post raise `SystemCallError` (they do not silently
  degrade). A `wait` on a *missing* name is not an error at all — it
  recreates the semaphore with value 1 (see the auto-recreate note above).
- `SemaphoreInterrupted` (subclass of `TryAgain`) is raised when a wait
  is interrupted; it propagates rather than being retried blindly.
- `with_retry` retries only on the listed retriable errnos
  (`ENOENT`, `EIDRM`, `EAGAIN`, `EMFILE`, `ENFILE`, `EINTR`;
  `semaphore.rb:123-132`) with exponential backoff and jitter; fatal
  errnos (`EINVAL`, `EACCES`) raise immediately.

### Load-time behavior

If the `inline` (RubyInline) gem cannot be loaded, the module logs
"semaphore synchronization will not work" and defines no C methods, so
every subsequent call fails with `NoMethodError` (`semaphore.rb:1-8`).
scout-essentials must also be loadable — see the note in *Architecture*:
`TryAgain` is defined by scout-gear's `scout/exceptions`, so on a
scout-gear-only load path `require 'scout/semaphore'` fails with
`NameError: uninitialized constant ScoutSemaphore::TryAgain`.
The failure is loud, never a silent no-op.

### Use cases

- Bounding the number of concurrent processes around a shared resource.
- Serializing file or database updates across processes.

### Known issue

See "The bounded-map helpers are not equivalent" above:
`fork_each_on_semaphore` (`semaphore.rb:337`) raises
`NoMethodError: undefined method 'fingerprint' for module Misc` on entry.
Prefer `thread_each_on_semaphore`, `with_semaphore` + explicit forks, or
`TSV.traverse(elems, cpus: n)`.

## Monitor (`lib/scout/monitor.rb`)

The methods live on `Scout` itself (`Scout.locks`, `Scout.job_info`, …),
defined by `require 'scout/monitor'`. They are *not* a concurrency
primitive: they never take a lock. It is a read-only introspection API
that `find -L`s over a fixed set of directories
(`LOCK_DIRS`, `PERSIST_DIRS`, `JOB_DIRS`, `SENSIBLE_WRITE_DIRS`) and parses
lock/persist/job state on disk. Its only in-repo consumers are
`scout_commands/system/status` and `scout_commands/system/clean`
(`scout system status` / `scout system clean`), and `require 'scout'` does
**not** load it — those two commands `require 'scout/monitor'` explicitly.

| Method | What it reports |
|---|---|
| `locks` / `lock_info` | `.lock` files under the lock dirs |
| `sensiblewrites` / `sensiblewrite_info` | sensible-write staging dirs |
| `persists` / `persist_info` | persistence locks and caches |
| `job_info(workflows, tasks, dirs)` | workflow jobs (`require 'rbbt/workflow/step'` at call time) |
| `file_time(file)` | `ctime`/`atime`/`elapsed` for a lock file |
| `dump_memory` | memory report |

Two traps worth knowing before you call these:

- The `dirs` arguments must be `Path` objects (`Path.setup(...)`), not
  plain Strings: `job_info` calls `dir.glob("*")` and a String raises
  `NoMethodError`. `job_info` also does `require 'rbbt/workflow/step'` at
  call time, so it needs the `rbbt` gem.
- `lock_info` reads `pid`/`ppid` from the YAML body of a `.lock` file; a
  lock that exists but has not been written yet is reported pid-less, not
  as an error. `file_time` has a latent bug: the
  `info[:ctime] = Time.now - 999` fallback sits *outside* its rescue, so
  for an existing file the returned `ctime` is clobbered and only
  `elapsed` is trustworthy.

## Known issues

- **Marshal limitations**: Work items and results must be
  Marshal-compatible (plain Strings and Integers take dedicated frames; see
  *IPC model*). Procs with closures, IO objects, and Thread objects are not
  serializable. (The worker *block* is not marshalled — workers are forked,
  so they inherit the block.)
- **Memory duplication**: Forked workers get a copy-on-write view of the
  parent's memory. For very large in-memory structures this can be
  significant.
- **WorkQueue is process-level**: it manages forked workers, not
  threads; `thread_each_on_semaphore` is the thread-based alternative.
- **Socket cleanup**: If a process exits abnormally, sockets may not be
  cleaned up, leaking file descriptors until GC.

## See also

- [Architecture](Architecture.md)
- [Concurrency probes](../../research/concurrency-probes.md)
- [TSV Internals](TSVInternals.md)
- [Running Parallel Work](../user/RunningParallelWork.md)
- [scout-essentials: Streaming Model](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/StreamingModel.md)
