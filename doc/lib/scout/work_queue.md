# WorkQueue: Parallel, Forking Job Processing in Ruby

The `WorkQueue` class and associated components implement a robust, parallel job execution system for Ruby, enabling dynamic distribution of workloads across multiple forked worker processes. Workers and the main queue communicate safely and efficiently through custom sockets, and errors are propagated and handled with care.

This documentation gathers the essential details and usage exemplars for WorkQueue and its major subcomponents, synthesizing best practices and edge-case handling from actual usage and comprehensive test coverage.

---

## Overview

A `WorkQueue` is a manager for a group of forked Ruby worker processes. Jobs are enqueued and dispatched to workers, which process them and send results or errors back to the parent process. Workers can be added or removed at runtime, and results may be handled as they arrive through callback mechanisms.

Key features include:

- Parallel processing with user-definable worker blocks.
- Safe and dynamic worker lifecycle management.
- Two-way inter-process communication through robust, custom socket mechanisms.
- Error propagation and abort semantics originating from both worker and callback errors.
- Explicit resource and process cleanup for high reliability.

---

## WorkQueue Usage

### Initialization and Processing

Instantiate a queue with the number of workers and a block to process each job:

```ruby
q = WorkQueue.new num do |obj|
  [Process.pid.to_s, obj.to_s] * " "
end
```

Start processing, collecting results via a callback:

```ruby
res = []
q.process { |out| res << out }
```

### Submitting Work and Closing the Queue

Jobs are submitted to the queue via `write`:

```ruby
reps.times do |i|
  q.write i
end
q.close
q.join
```

Jobs can be submitted from threads or in a spawned process:

```ruby
pid = Process.fork do
  reps.times { |i| q.write i }
end
Process.waitpid pid
q.close
q.join
```

### Ignoring Output

Call `ignore_ouput` if worker results do not need to be collected:

```ruby
q.ignore_ouput
```

No output will be delivered to your callback in this case:

```ruby
assert_equal 0, res.length
```

### Dynamic Worker Management

Add and remove workers as needed:

```ruby
q.remove_one_worker
w = q.add_worker { |obj| "HEY" }
```

---

## Exception Propagation and Robust Cleanup

### Worker and Callback Exceptions

- Exceptions raised in worker blocks (child process) are sent through the queue and re-raised in the main thread, aborting the queue and remaining workers.
- Likewise, exceptions in the callback block for `process` propagate in the same fashion.
- All failures result in prompt cleanup and process/socket resource release.

**Example:**

```ruby
q = WorkQueue.new num do |obj|
  raise ScoutException if rand < 0.1
  [Process.pid.to_s, obj.to_s] * " "
end

assert_raise ScoutException do
  # ... submit jobs, call join ...
end
```

### Socket-Level Signaling

- If a peer closes its socket write, subsequent reads raise a specific `ClosedStream` error for crisp stream termination signaling.
- Errors detected in socket operations or marshal (de)serialization bubble up as exceptions, enabling early detection of communication failures.

---

## Advanced Lifecycle and Resource Management

After queuing and processing, always call `join` to ensure:

- All worker processes have finished and cleaned up.
- The output reader and worker waiter threads are done.
- All pipes and sockets are clean and closed.

Optionally, call `clean` for explicit socket and state teardown.

---

## Internals: Sockets and Synchronization

Communication relies on custom `WorkQueue::Socket` objects, which serialize/deserialise Ruby objects safely between processes. Special sentinel objects (e.g., `DoneProcessing`) mark worker lifecycles, and exceptions can be serialized as result objects. Semaphores may be used to coordinate worker activity, preventing race conditions in shared resource access (such as files or pipes).

---

## Subtopics

### Exceptions

- Worker exceptions are always relayed to the main process for handling.
- Exceptions in callbacks abort the main queue execution.
- Reading from a closed stream raises `ClosedStream`.
- Test coverage asserts these behaviors for reliability and clarity in error state transitions.

### Socket

The socket abstraction (see `WorkQueue::Socket`) underpins safe serialization of objects—including control signals and exceptions—across process boundaries. Proper error and EOF signaling ensures the parent process discerns when streams end or are cut due to errors.

### Worker

Workers represent forked processes with controlled process lifecycle:

- **run**: Forks and runs user code in a new process.
- **process**: Establishes inbound job read, outbound result write, shuts down on `DoneProcessing`.
- **abort**: Sends INT for fast shutdown.
- **join**: Waits for OS-child reaping.
- **Exception relay**: Uncaught exceptions from worker code are caught, wrapped, and sent to the main process.

Workers are robust and support mass concurrency, as exemplified by tests that launch and synchronize hundreds of workers for coordinated concurrent output and exception handling.

---

## Summary

`WorkQueue` and its associated worker and socket components form a highly flexible and safe foundation for parallel, process-based workflows in Ruby. Whether running large task batches, handling dynamic changes in worker count, or needing robust and transparent error handling, `WorkQueue` provides the infrastructure for efficient, correct, and maintainable parallel job processing.

- Use for scalable, process-based parallelism.
- Rely on its strong error propagation and cleanup semantics.
- Extend by customizing worker and queue behaviors as needed.

With comprehensive test-driven validation, `WorkQueue` is a reliable primitive for any high-concurrency Ruby workload.