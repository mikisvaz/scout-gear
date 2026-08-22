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
| `write(obj)` / `<<` | Enqueue one item for the workers. |
| `add_worker { \|item\| ... }` | Fork one more worker (optionally with its own block). |
| `process { \|result\| ... }` | **Fork all workers** and start the reader thread; the block you give receives each *result* in the parent. Also starts the waiter thread that reaps exited workers. |
| `close` | Signal that no more input is coming (workers drain and exit). |
| `join(clean = true)` | Wait for reader + waiter threads, then `clean`. |
| `abort` | Tear the queue down after a failure. |
| `clean` | Close the socket pair. |

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
  *is* the fork-and-run step; feed items with `write`/`<<`; join with
  `join`. (Older docs describing `wq.add_inputs(...)` / `wq.run` described
  an API that does not exist in this codebase.)
- Blocks and anything they capture must be `Marshal`-serializable, because
  the worker body is marshalled to the forked workers. Avoid lambdas
  capturing IO objects, Procs over unserializable state, etc.
- A worker that dies abnormally raises in `join` (`Exception: Worker <pid>
  ended with status <n>`, work_queue.rb:137); a worker that raises inside
  the block sends the exception back over the output socket and it is
  re-raised in the parent's reader.
- `remove_one_worker` sends a `DoneProcessing` sentinel so one worker exits
  cleanly; `remove_worker(pid)` drops it from the reaper's list.

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
| `with_semaphore(size, file = nil, &block)` | Create a fresh semaphore of `size` around one block; safe for nested/subprocess use. |
| `thread_each_on_semaphore(elems, size, &block)` | Run block on each element with at most `size` concurrent *threads*. |
| `fork_each_on_semaphore(elems, size, file = nil, &block)` | Fork-based variant. **Currently broken** — see below. |

Behavior verified by probe (`research/doc_audit/probes/P032*`): creation,
existence checks, wait/post and `synchronize` all work; retry with jittered
backoff (up to 6 attempts) is applied on `ENOENT`-class errno; names are
normalized so lock-file paths map onto valid semaphore names.

### Failure mode — this matters

If RubyInline cannot compile the C extension (no compiler, no write access
to the inline cache), `require 'scout/semaphore'` logs
`semaphore synchronization will not work` and **does not define the C
functions**. Every call then raises `NoMethodError`. It does *not* degrade
to a no-op, so there are no silent races — but you must rescue the
`NoMethodError` (or ensure a toolchain is present) if your environment may
lack one.

### Known breakage

`ScoutSemaphore.fork_each_on_semaphore` currently raises
`NoMethodError: undefined method 'fingerprint' for module Misc` on entry
(semaphore.rb:337 calls `Misc.fingerprint`, which is defined in neither
scout-gear nor the scout-essentials it depends on; probe P032b). Use
`thread_each_on_semaphore`, `with_semaphore`, or a `WorkQueue` until this is
fixed.

## Common mistakes

- **Calling a nonexistent API**: `add_inputs`, `run`, `callback` do not
  exist. `process` forks and starts collection; `write` enqueues; `join`
  reaps.
- **Forgetting `close` + `join`**: workers only finish when you signal
  end-of-input and wait. Without `join`, exceptions from dead workers are
  lost.
- **Non-serializable worker blocks**: the block is marshalled to children;
  keep it free of IO/Proc/state that can't round-trip.
- **Expecting shared state**: workers are forked processes; in-memory state
  is copy-on-write isolated, so results must be returned through the queue
  (`into:` or the `process` callback), never through shared variables.
- **Assuming semaphores degrade silently**: they fail loudly
  (`NoMethodError`) when the C extension is unavailable.

## See also

- [Processing Tabular Data](ProcessingTabularData.md) — traversal options.
- [Caching Data](CachingData.md) — persistence used by parallel workers.
- [Concurrency Model](../developer/ConcurrencyModel.md) — the full
  concurrency model, streams and locks.
