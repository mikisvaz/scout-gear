# Semaphore (ScoutSemaphore)

ScoutSemaphore provides simple process/thread concurrency control primitives built on:

- POSIX named semaphores (via RubyInline C bindings to sem_open/sem_wait/sem_post/sem_unlink).
- Convenience helpers to scope a semaphore’s lifetime and run critical sections.
- Utilities to process collections concurrently with a bounded level of parallelism, using either processes (via TSV.traverse) or threads.

Requirements:
- RubyInline (gem ‘inline’) to compile the small C bindings at runtime.
- A platform with POSIX named semaphores (sem_open). If RubyInline is unavailable, Scout logs a warning and the module will not be functional.

Sections:
- Design and prerequisites
- API
  - with_semaphore
  - synchronize
  - fork_each_on_semaphore (process-based)
  - thread_each_on_semaphore (thread-based)
  - Low-level C bindings (create/delete/wait/post)
- Usage examples
- Notes and caveats

---

## Design and prerequisites

At its core, ScoutSemaphore exposes four C-bound singleton methods using RubyInline:

- create_semaphore(name, value) — sem_open(name, O_CREAT, …, value)
- delete_semaphore(name) — sem_unlink(name)
- wait_semaphore(name) — sem_wait on the named semaphore
- post_semaphore(name) — sem_post on the named semaphore

On top of these, high-level Ruby methods make it easy to:
- Create a semaphore for the duration of a block and guarantee cleanup (with_semaphore).
- Run a critical section by waiting, yielding, and posting (synchronize).
- Traverse a list with bounded concurrency, either via background processes (fork_each_on_semaphore) or threads (thread_each_on_semaphore).

If RubyInline cannot be loaded, a warning is emitted and none of these methods are defined (tests should skip accordingly).

---

## API

### with_semaphore(size, file = nil) { |sem_name| ... } → nil

Create a named semaphore with an initial count “size”, yield its name to the block, and destroy it afterwards.

- size: Integer initial tokens (maximum concurrent “holders”).
- file (String, optional): name/identifier for the semaphore. If nil, a unique name is generated, prefixed internally (e.g., “/scout-<digest>”). When a custom name is provided, slashes are sanitized.

Behavior:
- Logs creation and removal.
- Ensures sem_unlink on exit, even if the block raises.

Use this to scope semaphore lifetime and pass its name to other helpers or processes.

### synchronize(sem_name) { ... } → result

Wait on a named semaphore, run the critical section, then post it back.

- sem_name: the name returned by with_semaphore (or any existing semaphore name).
- Ensures that sem_post is called even if the block raises.

Exceptions:
- If sem_wait fails, a ScoutSemaphore::SemaphoreInterrupted (subclass of TryAgain) may be raised (see note below).

### fork_each_on_semaphore(elems, size, file = nil) { |elem| ... } → nil

Process a collection with at most “size” concurrent workers using TSV.traverse (process-based parallelism).

- elems: any enumerable (Array, TSV, IO, etc.; TSV.traverse-compatible).
- size: max concurrent workers (cpus).
- file: ignored for traversal (kept for API symmetry).

Behavior:
- Uses TSV.traverse with :cpus => size and a progress bar.
- Yields elem to the block in worker subprocesses.
- Logs and swallows Interrupts in workers.

Use this when you want process-level parallelism, isolation, and streaming integration via TSV.traverse.

### thread_each_on_semaphore(elems, size) { |elem| ... } → nil

Process a collection with at most “size” concurrent threads using a Ruby Mutex/ConditionVariable.

- elems: any enumerable.
- size: max concurrent threads.

Behavior:
- Spawns a thread per element but gates entry to the critical region so that only “size” threads run the block simultaneously.
- On any exception, logs and ensures remaining threads are terminated (kill).

Use this when threads are sufficient and you prefer not to fork.

---

## Low-level C bindings (via RubyInline)

These are provided as module singleton methods and used internally:

- ScoutSemaphore.create_semaphore(name:String, value:Integer) → void
- ScoutSemaphore.delete_semaphore(name:String) → void
- ScoutSemaphore.wait_semaphore(name:String) → Integer (0 on success; errno on error)
- ScoutSemaphore.post_semaphore(name:String) → void

Note:
- Named semaphores differ by platform. The auto-generated default names start with “/scout-…”. Custom names passed to with_semaphore are sanitized (slashes replaced), so prefer the default unless you have a specific need.

---

## Usage examples

Basic scoping and critical section:

```ruby
ScoutSemaphore.with_semaphore(1) do |sem|
  10.times do
    ScoutSemaphore.synchronize(sem) do
      # Only one process/thread will execute this at any time
      do_critical_work()
    end
  end
end
```

Process-based parallel map (bounded):

```ruby
items = (1..1000).to_a
ScoutSemaphore.fork_each_on_semaphore(items, 4) do |i|
  compute(i)            # up to 4 worker processes run concurrently
end
```

Thread-based parallel map (bounded):

```ruby
items = (1..1000).to_a
ScoutSemaphore.thread_each_on_semaphore(items, 8) do |i|
  compute_in_thread(i)  # up to 8 threads run concurrently
end
```

Coordination across processes:

```ruby
# In coordinator
ScoutSemaphore.with_semaphore(2) do |sem|
  # Start several worker processes; pass sem to each (e.g., via ENV, argv, IPC)
end

# In each worker process
sem = ENV["SCOUT_SEM"]
ScoutSemaphore.synchronize(sem) do
  # guarded work
end
```

---

## Notes and caveats

- RubyInline dependency: If ‘inline’ cannot be loaded, ScoutSemaphore logs a warning and does not provide these methods. Install the gem or guard your code.
- Semaphore naming: POSIX named semaphores are typically referenced by a leading “/” path-like name. The default generated names follow this. If you pass a custom name to with_semaphore, it is sanitized (slashes replaced) before creation; prefer defaults unless you’re coordinating with external code that expects a specific name.
- Error reporting: wait_semaphore returns errno on failure. synchronize currently checks for a specific return to raise SemaphoreInterrupted; in practice you will see exceptions only if the system-level wait fails.
- fork_each_on_semaphore: this helper doesn’t use OS-level semaphores; it leverages TSV.traverse with :cpus => size (process pool). Choose this when you need the TSV/Open streaming ecosystem and process isolation.
- thread_each_on_semaphore: the concurrency limit is enforced with a simple counter and Mutex/ConditionVariable; it is not an OS semaphore. It ensures threads are joined/killed on error, but still prefer robust error handling in your block.

ScoutSemaphore gives you simple, robust building blocks to bound concurrency and protect critical sections in both process- and thread-based strategies, while integrating nicely with the rest of Scout’s TSV/Open streaming infrastructure.