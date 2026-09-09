# Investigation: Concurrency — Probe Findings

> **Non-normative.** This document is a working investigation with
> implementation details, code exploration notes, and hypotheses. Refer
> to the authoritative docs (`doc/developer/ConcurrencyModel.md`,
> `doc/user/RunningParallelWork.md`) for the user-facing contract.

Consolidated record of the five probes run against the concurrency
subsystem (`lib/scout/work_queue.rb`, `lib/scout/work_queue/*.rb`,
`lib/scout/semaphore.rb`, `lib/scout/monitor.rb`) during the
documentation-consolidation campaign. Each probe was executed through
`Observation/probe(<name>)` and its receipt cached. Claim identifiers
below refer to the Cortex artifact `scout-gear/concurrency.md` (map
`current`, 19 claims / 5 receipts — C2.1-C2.10, C3.1-C3.6, C4.1-C4.3),
which holds the full evidence chains. (An earlier draft of this ledger and
of the campaign survey said "27 claims"; that was a miscount.)

> **Consolidation audit (2026-09-09, HEAD `8a3a514`).** All 19 claims were
> checked for representation in the doc pages (`doc/user/RunningParallelWork.md`,
> `doc/developer/ConcurrencyModel.md`, the Concurrency section of
> `doc/developer/Architecture.md`, README's subsystem table) — 19/19 present.
> Nine claims were re-verified directly at HEAD (8 deterministic single-process
> checks plus the fork-boxed `abort`/`join` hang, all reproduced); one
> probe-authored wording error was found and corrected (see
> `wq_semaphore_semantics` below). Two probes were intentionally not re-run —
> the cross-process semaphore race and `Step#fork(semaphore:)` end-to-end —
> under the campaign's fork-hazard discipline.
> Test-suite evidence and the file-by-file audit record live in the Cortex
> note `scout-gear/concurrency-consolidation.md` (map `current`).

All probes ran single-process or under a boxed `timeout`. The statements
below were first verified against HEAD
`8a3a514d7200971179573a1e3808c1ba3bb9226c` before promotion into
`doc/developer/ConcurrencyModel.md` (this file lives under `doc/developer/`,
not `doc/user/`), `doc/developer/Architecture.md`,
`doc/user/RunningParallelWork.md` and `README.md`.

## Probe ledger

### `wq_lifecycle_static`

- **Probed**: the WorkQueue surface without forking — what
  `WorkQueue.new(n, &block)` builds (two `Socket`s, `n` `Worker` objects
  with `pid == nil`, no threads), the full instance-method list, whether
  `add_inputs`/`run`/`callback` exist as commands, `close`/`join` called
  before `process`, the `DoneProcessing` hierarchy, and the worker
  246/ABRT protocol constants.
- **Finding**: construction forks nothing — `process` is the fork point
  and starts the reader + waiter threads. The API is exactly
  `process/write/close/join` plus `abort/clean` (and `add_worker`,
  `remove_one_worker`, `remove_worker`, `ignore_ouput`); there is no
  `add_inputs` and no `run`. `DoneProcessing < Exception` (not
  `StandardError`), so a bare `rescue` in a worker block does not swallow
  the shutdown sentinel; the waiter whitelists exit status 246 as the
  normal abort path.
- **Receipt**: `Observation/probe/wq_lifecycle_static_525867e0d008ee013c735a45249ce112.json`
- **Claims**: C2.1, C2.2, C2.3, C2.7

### `wq_fork_run`

- **Probed**: the forking path, boxed under `timeout` — result flow and
  per-worker ordering, `:ignore` and the `ignore_ouput` flag,
  worker-exception propagation, and the abort/clean interaction.
- **Finding**: per-worker FIFO order is preserved and items are
  distributed round-robin (2 workers over 1..8 split `[1,3,5,7]` /
  `[2,4,6,8]` in most runs — deterministic in this build but not a
  contract). A raising worker sends the *inner* exception back and
  `join` re-raises it in the parent. **`WorkQueue#abort` does not close
  the parent's output write-end, so a bare `wq.join` after `wq.abort`
  hangs indefinitely; `clean` is the required companion** — which is
  exactly why `TSV.traverse(cpus:)` pairs `rescue → queue.abort` with
  `ensure → queue.clean` (`lib/scout/tsv/open.rb:113-117`).
- **Receipt**: `Observation/probe/wq_fork_run_da96535a53997a47f526b18869bb0c2a.json`
- **Claims**: C2.4, C2.5, C2.6

### `wq_socket_framing`

- **Probed**: `WorkQueue::Socket#dump`/`#load` byte for byte — the
  5-byte `[size, type].pack('La')` header per type tag, round-trips for
  Integer/nil/Symbol/Array/String/exception/annotated objects, the
  signed-32-bit Integer limit, `concurrent_stream` stripping, and
  blocking behavior without a concurrent reader.
- **Finding**: the IPC layer is a 4-type tagged framing, not plain
  Marshal — Strings take a raw-bytes `C` frame and are never marshalled;
  Integers travel *in* the size field via `pack('l')`, so `dump(-1)`
  loads as `4294967295` and `dump(2**40)` as `0` (silent corruption
  outside signed 32-bit). `dump` writes with a raw loop and blocks
  indefinitely on a full pipe unless a reader drains concurrently — the
  mechanism behind the documented deadlock-avoidance rule.
- **Receipt**: `Observation/probe/wq_socket_framing_7be796261ae0a9e2306c89ef161b0d82.json`
- **Claims**: C2.8, C2.9, C2.10

### `wq_semaphore_semantics`

- **Probed**: single-process `ScoutSemaphore` semantics — name
  normalization and the `/dev/shm` backing store, the create/wait/post/
  delete lifecycle, `with_semaphore`, `synchronize` with a raising
  block, `thread_each_on_semaphore`'s concurrency bound and failure
  behavior, the missing-name path, and the `Misc.fingerprint` failure of
  `fork_each_on_semaphore`.
- **Finding**: `wait` on a **missing** name does not fail — it logs
  "appears missing", recreates the name with **value 1** and retries, so
  a typo'd or unlinked name is indistinguishable from a fresh semaphore
  (stale detection must use `exists?`). `synchronize` posts in an
  `ensure` even when the block raises, and post failures raise
  (deliberately). `thread_each_on_semaphore(elems, 3)` holds exactly 3
  concurrent threads but **swallows** a raising block (logs, kills the
  threads; see the audit correction below for what it actually returns).
  `fork_each_on_semaphore` is broken on entry:
  `NoMethodError: undefined method 'fingerprint' for module Misc`
  (`semaphore.rb:337`); the fingerprint API now lives on `Log`.
- **Receipt**: `Observation/probe/wq_semaphore_semantics_da869a640094600c2036d6ce2f793444.json`
- **Claims**: C3.1, C3.2, C3.3, C3.4, C3.5

> **Audit correction (2026-09-09).** This entry originally said
> `thread_each_on_semaphore` "logs, kills the threads, returns `nil`".
> That return value was an inference from the probe's own prose, not an
> observation — the probe labelled the rescue path "swallowed (returns
> nil)" without inspecting the return value. Re-verified at HEAD
> `8a3a514` in a single-process scratch run: the method returns the
> **array of `Thread` objects** on both the happy and the raising path.
> On the happy path the block's results are in `thread.value`; on the
> raising path every thread is dead with the error pending, so
> `thread.value` re-raises it. The exception is still swallowed by the
> method itself — that half of the claim stands. Both doc pages and the
> claims artifact now state the actual return contract.

### `wq_monitor_api`

- **Probed**: the undocumented `lib/scout/monitor.rb` — which `Scout.*`
  methods it defines, the directory constants it scans, `lock_info`'s
  parsing of `.lock` YAML bodies, and `job_info`/`file_time` argument
  and dependency requirements.
- **Finding**: monitor is a read-only introspection API (never takes a
  lock) for `scout system status`/`clean`; it is *not* loaded by
  `require 'scout'` — the two commands require it explicitly.
  `lock_info` reads `pid`/`ppid` from the YAML body, so an unwritten
  lock is reported pid-less rather than as an error. `job_info` needs
  `Path`-typed dirs (a String raises `NoMethodError` on `glob`) and
  does `require 'rbbt/workflow/step'` at call time. `file_time` has a
  latent bug: the `ctime = Time.now - 999` fallback sits outside its
  rescue, so for an *existing* file the returned `ctime` is clobbered
  and only `elapsed` is trustworthy.
- **Receipt**: `Observation/probe/wq_monitor_api_1d49045bd529c9b0f9a4e0004e6c1558.json`
- **Claims**: C4.1, C4.2, C4.3

> **Coverage note.** C3.6 (deployment resource limits are enforced by the
> local executor's `check_resources` counter, not by semaphores; the
> `Step#fork(semaphore:)` parameter is unused in-repo) is a code-reading
> finding in the claims artifact and carries **no probe receipt** — its
> evidence is a `grep` over `lib/` and `scout_commands/`, not an
> `Observation/probe` job. It is counted in the 19 but not in the 5.

## Consolidated observations

Three threads run through the five probes:

1. **The teardown contract is the load-bearing undocumented fact.**
   Abort kills children but leaves the parent's write-end open, so the
   reader never sees EOF. Every safe caller must pair `abort` with
   `clean` (or close the output write-end). This is now documented in
   both doc pages as behavior plus an explicit warning, and it explains
   why `TSV.traverse(cpus:)` is safe as written.

2. **Silent degradation is the recurring failure shape.** Integer frames
   truncate, missing semaphores recreate with value 1, and
   `thread_each_on_semaphore` eats exceptions. None of these raise where
   a caller would notice; all three are now stated in the docs as
   warnings, and the two that are genuine code defects (Integer
   truncation, `Misc.fingerprint`) are recorded below rather than
   promoted as normal behavior.

3. **The concurrency subsystem has three unrelated layers** — WorkQueue
   (fork pool + tagged-frame IPC), ScoutSemaphore (named POSIX
   semaphores backing the IPC frame locks), and Monitor (read-only
   introspection that merely lives in the same directory). Monitor was
   documented nowhere and is now covered by a short section rather than
   a new page, following the repo's convention of keeping one
   subsystem doc per area.

## Deliberately not promoted (live-code defects)

These are behaviors of the code that the docs now describe as warnings
or workarounds, not as normal behavior, because documenting them as
normal would freeze a defect. Improvements.md candidates:

- `WorkQueue#abort` should close `@output.swrite` (or `join` should not
  wait on a reader that can never be satisfied). *(C2.6)*
- `Socket#dump` Integer frames truncate at signed 32-bit; it should
  raise or marshal out-of-range Integers. *(C2.8)*
- `ScoutSemaphore.fork_each_on_semaphore` calls `Misc.fingerprint`;
  should be `Log.fingerprint`. *(C3.5)*
- `Scout.file_time`: the `info[:ctime] = Time.now - 999` line must be
  inside the rescue. *(C4.3)*
- `ScoutSemaphore.wait_semaphore` auto-recreates missing names with
  value 1; a `strict:` opt-out would make stale-name detection
  possible. *(C3.3)*
- `thread_each_on_semaphore` swallows exceptions; it returns the `Thread`
  array, so a caller has no signal that work was lost unless it inspects
  each `thread.value`. *(C3.4)*

## Deliberately left open

- Cross-process semaphore contention under real concurrency (two OS
  processes racing wait/post on one name) — single-process semantics
  are probed; the fork-and-race variant is the exact hang class the
  campaign's fork-hazard discipline avoids.
- `Step#fork(semaphore:)` end-to-end — code-reading only; the wrapper is
  three lines around already-probed `synchronize`, and no in-repo
  caller passes a semaphore (`local.rb:243` calls `job.fork(true)`).
