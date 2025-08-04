# Exceptions in WorkQueue: Error Propagation, Control Flow, and Robustness

WorkQueue employs a structured system for error detection, propagation, and control signaling between the parent process, worker processes, and communication threads. This ensures not only robust error handling, but also orderly lifecycle transitions (such as worker termination) and clean shutdowns in the face of faults or normal completion.

## Sentinel Exceptions and Error Objects

### `DoneProcessing`

A special sentinel exception object, `DoneProcessing`, is used within WorkQueue as a cross-process/end-of-work indicator. When a worker completes its assigned tasks or is instructed to shut down, it sends a `DoneProcessing` object containing its process ID. This is recognized by the main queue reader, allowing the system to track which workers have finished and to coordinate an orderly shutdown.

#### Example from Tests

Workers are removed by sending `DoneProcessing` through the queue's input socket:

```ruby
(num - 1).times do q.remove_one_worker end
```

The main process monitors for completion using this sentinel:

```ruby
while true
  obj = @output.read
  if DoneProcessing === obj
    # handle worker shutdown
  end
end
```

### `WorkerException`

If a worker process raises an uncaught exception during its task execution, WorkQueue captures this and encapsulates it in a `WorkerException`, which is then sent through the output socket:

```ruby
class WorkerException < ScoutException
  attr_accessor :worker_exception, :pid
  def initialize(worker_exception, pid)
    @worker_exception = worker_exception
    @pid = pid
  end
end
```

In the parent process, receiving a `WorkerException` triggers abort handling. The error is logged, the queue aborts, all workers are signaled to terminate, and the original exception is re-raised in the callback/join context. This is tested in scenarios such as:

```ruby
q = WorkQueue.new num do |obj|
  raise ScoutException if rand < 0.1
  # ...
end

assert_raise ScoutException do
  # WorkQueue processing/join
end
```

### General Exception Propagation

If exceptions occur in the callback block provided to `process`, those are also relayed as fatal to the outer join context, ensuring that both worker-side and callback-side errors are handled:

```ruby
q.process do |out|
  raise ScoutException 
  # ...
end
```

### Abortion and Cleanup on Error

Upon any exception in a worker or in result-handling threads, WorkQueue:

- Aborts all remaining worker processes.
- Releases any held semaphores to avoid potential deadlocks.
- Cleans up resources including sockets and threads.
- Reraises the exception at the `join` call site for explicit user handling.

Test coverage confirms this:

```ruby
assert_raise ScoutException do
  begin
    t.join
    q.join(false)
  rescue
    t.raise($!)
    raise $!
  ensure
    t.join
    q.clean
  end
end
```

### Stream/Socket-Level Exceptions

If communication channels (sockets) are closed or fail unexpectedly, specific exceptions such as `ClosedStream` may be raised, signaling the end of input/output to the receiver for clean stream termination.

---

## Summary

- `DoneProcessing` and `WorkerException` provide structured, transportable signals for orderly worker shutdown and error traceback between workers and the main queue.
- All user code and callback exceptions are reliably propagated and lead to queue abortion and resource cleanup.
- Socket-level errors are reported as exceptions; cleanup code is robust in the face of such failures.
- Test-driven edge-case handling underpins all exception semantics in WorkQueue, ensuring reliable, predictable reaction to error states, partial failures, and end-of-work transitions.