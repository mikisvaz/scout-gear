# Running Parallel Work

This document explains how to distribute computation across multiple
processes using scout-gear's `WorkQueue`, and how to coordinate those
processes with the `ScoutSemaphore` primitives that come with it.

It is intended for workflow authors who need CPU-level parallelism in Ruby.

## What problem does this solve?

Ruby's Global Interpreter Lock (GVL) means threads do not give you true CPU
parallelism. To use multiple cores you need multiple *processes* — and
multiprocessing in Ruby leaves you with real problems: distributing work,
collecting results, propagating exceptions, and not leaking processes.
`WorkQueue` wraps all of that.

- Fork N worker processes.
- Feed work items to the queue.
- Workers process items and send results back.
- Results and worker exceptions are collected in the parent process.

## When do I use it?

- Traversing large TSV datasets with `cpus:` (the most common entry point).
- Running many independent computations across a process pool.
- When you need true parallelism that Ruby threads cannot provide.

## `TSV.traverse` with `cpus:` — the common path

You rarely instantiate `WorkQueue` yourself. `TSV.traverse` does it for you
when you pass `cpus:` (scout-gear `lib/scout/tsv/open.rb:36`, `:92`):

```ruby
require 'scout'

tsv = TSV.open("data.tsv", type: :list)
result = {}
TSV.traverse tsv, cpus: 4, into: result do |key, values|
  [key, values.collect { |v| v.to_i * 2 }]
end
```

- `into:` accepts a `Hash`/`TSV` (merged by key), an `Array`/`Set` (appended),
  a `TSV::Dumper` or an `IO`/`StringIO` (written as lines), or `nil` for
  streaming consumption.
- Workers receive `key` and the value slice determined by the traversal
  options; results are merged in the parent in traversal order per worker.
- `unnamed:` (default `true`) controls whether values arrive as raw data or
  with entity annotations attached.
- The queue is created, run, joined, and cleaned up entirely inside the call.

If you only need a progress bar over a single process, `bar:` does that
without forking.

## Using `WorkQueue` directly

The class is `WorkQueue` (`lib/scout/work_queue.rb`). Its real lifecycle is
smaller than it looks:

| Method | What it does |
|---|---|
| `WorkQueue.new(workers = 0, &block)` | Creates the queue and N worker stubs; the block is the worker body. Workers are **not** started yet. |
| `write(obj)` | Enqueue one item for the workers (there is no `<<`). |
| `add_worker { \|item\| ... }` | Fork one more worker (optionally with its own block). |
| `process { \|result\| ... }` | **Fork all workers** and start the reader thread; the block you give receives each *result* in the parent. Also starts the waiter thread that reaps exited workers. |
| `close` | Signal that no more input is coming: one `DoneProcessing` sentinel per worker; workers drain and exit. |
| `join(clean = true)` | Wait for reader + waiter threads, then `clean`. |
| `abort` | Kill the workers after a failure (see the warning below). |
| `clean` | Close both sockets and delete their semaphores. |

So the canonical pattern is:

```ruby
require 'scout/work_queue'

wq = WorkQueue.new(4) do |item|
  item ** 2               # worker body: runs in the child processes
end

wq.process do |result|    # forks workers; this block runs in the parent
  results << result
end

(1..5).each { |i| wq.write i }

wq.close
wq.join
# results = [1, 4, 9, 16, 25]  (any per-worker order)
```

Notes that matter in practice:

- There is **no `add_inputs`, no `run`, and no `callback`**. `process`
  *is* the fork-and-run step; feed items with `write`; join with `join`.
  (Older docs describing `wq.add_inputs(...)` / `wq.run` described an API
  that does not exist in this codebase.)

- `abort` **needs `clean` to finish the teardown.** `abort` kills the worker
  processes but does *not* close the parent's write-end of the output
  socket, so the reader thread never sees end-of-stream: a bare `wq.join`
  after `wq.abort` hangs forever. Put `clean` in an `ensure` — that is
  exactly what `TSV.traverse(cpus:)` does internally:

  ```ruby
  begin
    wq.process { |r| sink << r }
    items.each { |i| wq.write i }
    wq.close
    wq.join
  rescue Exception
    wq.abort
    raise
  ensure
    wq.clean
  end
  ```

- Work *items and results* must be `Marshal`-compatible (unless they are
  plain Strings or Integers, which take dedicated frames): no file handles,
  IO objects, Procs or Threads. The worker *block itself* is not
  marshalled — workers are forked and inherit it, so the block may capture
  anything, including Procs.
- Integer items and results are **not** marshalled: they travel inside the
  4-byte frame header and are truncated to signed 32-bit — `wq.write(-1)`
  comes back as `4294967295`, and anything at or above `2**31` wraps
  silently. Keep Integer payloads inside the signed 32-bit range (see
  [Concurrency Model](../developer/ConcurrencyModel.md)).
- A worker that dies abnormally raises in join with `Exception: Worker
  <pid> ended with status <n>` (work_queue.rb:123). A worker that raises
  inside the block sends the exception back over the output socket and it
  is re-raised in the parent's reader.
- `remove_one_worker` sends a `DoneProcessing` sentinel so one worker exits
  cleanly; `remove_worker(pid)` drops it from the reaper's list.

## Ordering

Per worker, results come back in the order that worker consumed its items —
never reordered within one pid. Across workers there is no cross-item
ordering contract: the parent's callback interleaves whatever the reader
thread drains next, so the global sequence depends on worker timing. (With
two workers over 1..8 the split is usually `[1,3,5,7]` / `[2,4,6,8]`, but
that is an artifact of the scheduling, not a promise.) If you need a
deterministic global order, sort or key the results afterwards.

Two further result-suppression details: a worker block that returns the
symbol `:ignore` has that result dropped, and `WorkQueue#ignore_ouput` (the
misspelling is the real method name) drops *all* results for a worker.

## Streaming inputs

`write` is incremental — you can enqueue while workers run:

```ruby
wq.process { |r| sink << r }
File.open("huge.txt") do |f|
  f.each_line { |line| wq.write line }
end
wq.close
wq.join
```

Items are drained through a socket pair as they arrive, so memory stays
bounded by the socket buffers, not by the input size.

## Synchronizing concurrent access

For cross-process coordination of a shared resource (a TokyoCabinet
database, a file), scout-gear ships POSIX *named semaphores* built with
RubyInline (`lib/scout/semaphore.rb`). The module is **`ScoutSemaphore`**
(names live in `/dev/shm/sem.scout*`):

```ruby
require 'scout/semaphore'

ScoutSemaphore.synchronize("my_resource") do
  # at most N processes in this block (N = :size when the semaphore was created)
  database_write(data)
end
```

The operations, all module functions on `ScoutSemaphore`:

| Function | Behavior |
|---|---|
| `ensure_or_create(name, size = 1)` | Create/open a named semaphore with `size` permits; returns success. |
| `exists?(name)` | Whether the name is live under `/dev/shm`. |
| `wait_semaphore(name)` / `post_semaphore(name)` | Acquire/release one permit (retry with backoff on transient errno). |
| `synchronize(name, &block)` | Wait, run block, post (ensured). Accepts either a raw name or a lock path — paths are normalized to a valid POSIX name. |
| `with_semaphore(size, file = nil, &block)` | Create a fresh semaphore of `size` around one block and delete it afterwards. Subprocesses started inside the block can `synchronize` on the yielded name; **the name is gone when the block ends**, so re-entering the same name later hits the auto-recreate path (see below). |
| `thread_each_on_semaphore(elems, size, &block)` | Run block on each element with at most `size` concurrent *threads*. **Swallows exceptions** — see below. |
| `fork_each_on_semaphore(elems, size, file = nil, &block)` | Fork-based variant. **Currently broken** — see below. |
| `delete_semaphore(name)` | Remove a named semaphore (returns `0` on success). |

Creation, existence checks, wait/post and `synchronize` all work; retry
with jittered backoff (up to 6 attempts) applies on `ENOENT`-class errno;
names are normalized so lock-file paths map onto valid semaphore names
(probe record: `research/concurrency-probes.md`).

Two more behaviors that are easy to miss:

- **A missing semaphore is silently recreated with value 1.** `wait` on a
  name that does not exist (typo, or deleted by a previous
  `with_semaphore`) does not fail — it logs "appears missing", creates the
  name with 1 permit and proceeds. Check with `ScoutSemaphore.exists?`
  if you need to detect a stale name; a `wait` will never tell you.
- **`synchronize` releases the permit even if the block raises**, and
  `thread_each_on_semaphore` swallows a raising block: it rescues
  `Exception` itself, logs it, kills the threads ("Ensuring threads are
  dead: N") and returns the array of (now dead) `Thread` objects — never
  the block's results, never the error. Do not use it for work that must
  not be lost.

### Failure mode — this matters

If RubyInline cannot compile the C extension (no compiler, no write access
to the inline cache), `require 'scout/semaphore'` logs
`semaphore synchronization will not work` and **does not define the C
functions**. Every call then raises `NoMethodError`. It does *not* degrade
to a no-op, so there are no silent races — but you must rescue the
`NoMethodError` (or ensure a toolchain is present) if your environment may
lack one. The file also references scout-essentials' `TryAgain` at load
time, so `require 'scout/semaphore'` needs both the `inline` gem and
scout-essentials on the path.

### Known breakage

`ScoutSemaphore.fork_each_on_semaphore` currently raises
`NoMethodError: undefined method 'fingerprint' for module Misc` on entry
(semaphore.rb:337 calls `Misc.fingerprint` to build a progress-bar title;
the fingerprint API now lives on `Log` — `Log.fingerprint` — so the fix is a
one-line change). Use `thread_each_on_semaphore` (mind its exception
swallowing), `with_semaphore` with explicit forks, or a `WorkQueue` until
this is fixed.

## Common mistakes

- **Calling a nonexistent API**: `add_inputs`, `run`, `callback` do not
  exist. `process` forks and starts collection; `write` enqueues; `join`
  reaps.
- **`WorkQueue#abort(exception)`**: the queue's `abort` takes no argument;
  `abort(exception)` is `WorkQueue::Socket#abort`.
- **Forgetting `close` + `join`**: workers only finish when you signal
  end-of-input and wait. Without `join`, exceptions from dead workers are
  lost.
- **Non-serializable work items**: items and results must be
  Marshal-compatible (Strings and Integers excepted); the worker block is
  forked, not marshalled, so it may capture anything.
- **Expecting shared state**: workers are forked processes; in-memory state
  is copy-on-write isolated, so results must be returned through the queue
  (`into:` or the `process` callback), never through shared variables.
- **Assuming semaphores degrade silently**: they fail loudly
  (`NoMethodError`) when the C extension is unavailable.
- **Relying on `abort` alone**: `abort` does not close the parent's output
  write-end, so a bare `join` afterwards hangs forever. Always follow
  `abort` with `clean` (ideally in an `ensure`).
- **Trusting semaphore names to be unique**: names are global on the host
  (`/dev/shm/sem.<name>`), are not namespaced per user or process, and a
  `wait`/`post` on a missing name silently recreates it with one permit —
  a typo cannot be detected at the call site.

## See also

- [Processing Tabular Data](ProcessingTabularData.md) — traversal options.
- [Caching Data](CachingData.md) — persistence used by parallel workers.
- [Concurrency Model](../developer/ConcurrencyModel.md) — the full
  concurrency model, streams and locks.
