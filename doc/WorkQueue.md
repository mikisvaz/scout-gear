# WorkQueue

WorkQueue is a lightweight, multi-process work pipeline that uses forked workers and IPC pipes to process a stream of objects in parallel. It provides:

- A queue with input/output sockets guarded by semaphores for safe concurrent access across processes.
- Worker processes that loop over input items, apply a user function, and emit results.
- Clean shutdown via sentinels; dynamic scaling (add/remove workers).
- Robust error propagation from workers to the main process.
- Efficient serialization (optimized for Strings/Integers, Marshal for general objects and annotated objects).

Core components:
- WorkQueue — orchestrates sockets, workers, reader/waiter threads, lifecycle.
- WorkQueue::Worker — manages a single forked worker’s lifecycle and processing loop.
- WorkQueue::Socket — typed pipe with serialization and semaphores.
- Exceptions: DoneProcessing sentinel and WorkerException wrapper.

---

## Quick start

Process items with multiple workers and collect results:

```ruby
num_workers = 10

q = WorkQueue.new(num_workers) do |obj|
  # User function runs in each worker process
  [Process.pid.to_s, obj.to_s] * " "
end

results = []
q.process do |out|
  results << out                 # Outgoing results seen in the parent
end

# Enqueue work (can be done from other threads or processes)
1_000.times { |i| q.write i }

q.close   # Signal no more input (sends sentinel for each worker)
q.join    # Wait for completion and cleanup

puts results.length  # => 1000
```

Ignore outputs:

```ruby
# Either return :ignore from worker proc
q = WorkQueue.new(10) { |obj| :ignore }

# Or mark workers to ignore outputs
q.ignore_ouput
```

Scale workers dynamically:

```ruby
# Remove workers gracefully (one at a time)
3.times { q.remove_one_worker }

# Add another worker with a different function
q.add_worker { |obj| "SPECIAL: #{obj}" }
```

---

## WorkQueue

Constructor:
- WorkQueue.new(workers = 0, &worker_proc)
  - workers: initial number of workers (Integer/String).
  - worker_proc: block run in each worker to process input objects.

Core attributes and methods:
- queue_id -> a stable identifier "[object_id]@[pid]".
- process(&callback)
  - Starts workers with worker_proc, a background reader to consume output and call the callback, and a waiter to reap pids.
  - Returns immediately; threads run in background until join.
- write(obj)
  - Enqueue an object into input; serialized and delivered to workers.
  - If an input-side exception was recorded (via input socket abort), write re-raises it.
- close
  - Signal end-of-input: sends a DoneProcessing sentinel per worker.
- join(clean = true)
  - Wait for reader/waiter threads to finish. When clean=true, closes sockets and removes semaphores.
- abort
  - Stop all workers (kill INT), post semaphores to unblock waiters, and mark the queue aborted.
- add_worker(&block)
  - Add a new worker dynamically; block overrides worker_proc for that worker.
- remove_one_worker
  - Gracefully remove one worker by sending a DoneProcessing sentinel into the input.
- ignore_ouput
  - Mark all current workers to not write results (sic: method name is misspelled to match implementation).
- remove_worker(pid)
  - Internal bookkeeping after a worker exits; prunes @workers and tracks removed pids (used to compute done count).
- clean
  - Join waiter (if any) and clean both sockets/semaphores.

Lifecycle notes:
- process spawns:
  - A reader thread: pops output items and calls your callback; finishes when all workers signal DoneProcessing.
  - A waiter thread: waits on worker pids and removes them from the pool.

Error behavior:
- If a worker raises, it is wrapped in WorkerException and written to output. The reader thread logs, aborts the queue, forwards the original exception via input abort, and raises the underlying exception in the parent.

---

## Worker

A managed forked worker that can run a block or a processing loop on sockets.

- WorkQueue::Worker.new(ignore_output = false)
  - ignore_output controls whether the worker writes results back (also controlled globally via queue.ignore_ouput).
- run { ... }
  - Forks; in child, sets INT trap to exit(-1), logs start, evals the block, then exits(0).
- process(input, output) { |obj| ... }
  - Forks; in child:
    - Purges inherited pipes (Open.purge_pipes); closes the queue’s write end if provided, to avoid deadlocks.
    - Loop: obj = input.read until EOF or sentinel:
      - If obj is DoneProcessing, writes DoneProcessing to output and exits cleanly.
      - Else, res = block.call(obj); writes res to output unless ignore_output or res == :ignore.
    - On exceptions (other than DoneProcessing/Interrupt), writes WorkerException($!, pid) to output and exits(-1).
- abort
  - Sends INT to worker pid (best-effort).
- join
  - Wait for this worker’s pid to exit.
- Worker.join([workers])
  - Wait for all provided workers until no child remains.

Identifiers:
- worker_short_id — object_id@pid
- worker_id — worker_short_id->queue_id (after queue assignment)

---

## Socket

A typed, semaphore-protected pipe abstraction used by the queue and workers.

Construction:
- WorkQueue::Socket.new(serializer = Marshal)
  - serializer must respond to dump/load; default Marshal.
  - Creates an IO.pipe pair (sread, swrite) and two named semaphores (write_sem, read_sem).

Serialization protocol (length-prefixed):
- Integer: pack with code "I" → faster than Marshal for counters.
- nil: code "N".
- String: code "C", payload is the raw string.
- Annotation::AnnotatedObject or general Ruby object: code "S", payload is serializer.dump(obj).

API:
- push(obj) / write(obj)
  - Serialize and write atomically under write semaphore.
- pop / read
  - Read one object atomically under read semaphore. If it is ClosedStream, raises ClosedStream (ended writer). If DoneProcessing is received, returns the sentinel, which the worker and queue treat specially.
- close_write
  - Writes ClosedStream sentinel, then closes swrite; subsequent reads will raise ClosedStream.
- close_read
  - Closes sread.
- clean
  - Close both ends (if open) and delete semaphores.
- abort(exception)
  - Record an exception on the socket; future writes (queue.write) will raise it.

Notes:
- Semaphores (ScoutSemaphore) ensure that concurrent processes/threads do not interleave frames when reading/writing on shared pipes.
- Open.read_stream ensures bounded reads of exact sizes.

---

## Exceptions

- DoneProcessing < Exception
  - Sentinel signaling a worker has finished processing input. Carries pid in message and attribute. Workers pass this through from input to output on shutdown.
- WorkerException < ScoutException
  - Wraps a worker-side exception and its pid; emitted on output when a worker fails.

Main-thread behavior:
- The reader thread re-raises WorkerException.worker_exception (after aborting the queue), surfacing the original cause.

---

## Patterns and recommendations

- Standard parallel map:

  ```ruby
  q = WorkQueue.new(Etc.nprocessors) { |obj| compute(obj) }
  out = []
  q.process { |res| out << res }
  items.each { |i| q.write i }
  q.close
  q.join
  ```

- Fire-and-forget additions during processing:
  - You can call q.write while the queue is processing; input is thread-safe.
  - Adding/removing workers works concurrently.

- Optional filtering:
  - Return :ignore from the worker proc to skip writing an output for an item.
  - Or call q.ignore_ouput to silence outputs from all workers.

- Graceful resize:
  - q.remove_one_worker injects DoneProcessing, causing one worker to exit cleanly.
  - You can repeat to downscale; add_worker to scale up again.

- Error handling:
  - If workers raise, expect WorkerException to be emitted; q.process rescues, logs and aborts, and re-raises in the parent.
  - If the main callback raises, join will propagate (see tests); wrap q.process body if you want to handle errors yourself.

- Cleanup:
  - Always call q.close followed by q.join to ensure sockets and semaphores are cleaned.
  - On error, ensure q.clean is called (join(clean=false) lets caller decide).

---

## Advanced usage

- Custom serializer:
  ```ruby
  require 'oj'
  sock = WorkQueue::Socket.new(Oj)  # Oj must implement dump/load
  ```
  WorkQueue itself constructs sockets with Marshal; roll your own workers/sockets if you need alternative serialization.

- Raw Worker + Sockets:
  ```ruby
  input  = WorkQueue::Socket.new
  output = WorkQueue::Socket.new
  workers = 4.times.map { WorkQueue::Worker.new }
  workers.each do |w|
    w.process(input, output) { |obj| obj.to_s.reverse }
  end
  # write/read; send DoneProcessing 4 times; close; join
  ```

- IPC correctness:
  - Workers call Open.purge_pipes in child to avoid inherited descriptors interfering with semaphores/IO.

---

## API quick reference

WorkQueue:
- new(workers = 0, &worker_proc)
- process(&callback)
- write(obj)
- close
- join(clean = true)
- abort
- add_worker(&block)
- remove_one_worker
- ignore_ouput  # sic: misspelled in code
- clean
- queue_id

Worker:
- new(ignore_output = false)
- run { ... }
- process(input, output) { |obj| ... }
- abort
- join
- self.join(workers)
- worker_short_id / worker_id
- pid, queue_id accessors

Socket:
- new(serializer = Marshal)
- write(obj) / push(obj)
- read / pop
- close_write / close_read
- clean
- abort(exception)
- socket_id, sread, swrite, write_sem, read_sem accessors

Exceptions:
- DoneProcessing.new(pid = Process.pid)
- WorkerException.new(worker_exception, pid)

---

## Examples

Remove workers, then add a special worker mid-flight:

```ruby
num = 10
reps = 10_000

q = WorkQueue.new(num) { |obj| "#{Process.pid} #{obj}" }

output = []
q.process { |out| output << out }

reps.times { |i| q.write i }

(num - 1).times { q.remove_one_worker }     # shrink to one worker

q.add_worker { |obj| "SPECIAL" }           # extra worker with unique behavior

reps.times { |i| q.write i + reps }

q.close
q.join

output.include?("SPECIAL")  # => true
```

Handle errors from workers:

```ruby
q = WorkQueue.new(5) do |_|
  raise ScoutException, "worker failure"
end

q.process { |_| }    # not used; will error before callback

begin
  100.times { |i| q.write i }
  q.close
  q.join(false)
rescue ScoutException
  # original worker exception surfaced here
ensure
  q.clean
end
```

Use a worker directly:

```ruby
input  = WorkQueue::Socket.new
output = WorkQueue::Socket.new

w = WorkQueue::Worker.new
w.process(input, output) { |x| x * 2 }

Thread.new do
  10.times { |i| input.write i }
  input.write DoneProcessing.new
end

vals = []
loop do
  v = output.read
  break if DoneProcessing === v
  vals << v
end

w.join
input.clean
output.clean
```

---

WorkQueue focuses on simple, robust multi-process parallelism: feed a stream of items, process them in forked workers, get results back, and shut down cleanly. Use it when you need fast, CPU-parallel pipelines with minimal overhead and clear failure propagation.