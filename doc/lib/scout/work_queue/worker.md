# WorkQueue::Worker

The `WorkQueue::Worker` class forms the process-level workhorse of the `WorkQueue` system, encapsulating robust, parallel execution of task blocks in separate forked Ruby processes. Workers communicate through custom sockets, cleanly relay exceptions, and support dynamic concurrency scaling—features heavily tested under high load and error conditions.

## Overview

A `WorkQueue::Worker` manages the lifecycle, error propagation, and inter-process communication for a child process intended to run user-supplied code blocks. This class ensures safe parallelism, controlled output, and reliable synchronization using core Ruby primitives and extra coordination constructs like semaphores.

### Capabilities

- **Process Isolation:** Each worker is a separate forked process.
- **Controlled I/O:** Workers process jobs from an input source and write results or errors to an output channel—by default, via `WorkQueue::Socket` for safe object serialization.
- **Error Relay:** Uncaught exceptions in the worker are sent back to the parent as `WorkerException` instances.
- **Shutdown and Joining:** Workers can be aborted, joined, or collectively reaped.
- **Output Filtering:** Suppress output results via the `ignore_ouput` flag or returning `:ignore` within blocks.

---

## Usage Patterns and Idioms

### Simple Process Forking and Completion

Workers execute code in a child process and can be synchronized for result observation, as shown by:

```
worker = WorkQueue::Worker.new
TmpFile.with_file do |file|
  worker.run do
    Open.write file, "TEST"
  end
  worker.join

  assert_equal "TEST", Open.read(file)
end
```
(`test_simple`)  
A single worker writes to a file and ensures the parent observes completion.

### High-Concurrency Coordination

Workers are robustly managed in bulk, leveraging semaphores for atomic access to shared resources and ensuring output order and completeness even under massive parallelism:

```
ScoutSemaphore.with_semaphore 1 do |sem|
  sout = Open.open_pipe do |sin|
    workers = num_workers.times.collect{ WorkQueue::Worker.new }
    workers.each do |w|
      w.run do
        ScoutSemaphore.synchronize(sem) do
          sin.puts "Start - #{Process.pid}"
          num_lines.times do |i|
            sin.puts "line-#{i}-#{Process.pid}"
          end
          sin.puts "End - #{Process.pid}"
        end
      end
    end
    sin.close

    WorkQueue::Worker.join(workers)
  end
  ...
end
```
(From `test_semaphore_pipe` and `test_semaphore`)  
These tests launch hundreds of worker processes and use a semaphore to serialize writes, verifying correctness and order even under contention.

### Processing Streams and Custom Control

Using `process`, workers continuously read from an input, process items, and write results until a termination signal is received:

```
workers = 10.times.collect{ WorkQueue::Worker.new }
workers.each do |w|
  w.process(input, output) do |obj|
    [Process.pid, obj.inspect] * " "
  end
end

# Writing jobs and termination signals
100.times { |i| input.write i }
10.times { input.write DoneProcessing.new }
input.close_write
```
(Ref: `test_process`)  
The workers handle batches of items and gracefully recognize and act upon `DoneProcessing` signals.

### Exception Handling and Detection

Robust error handling is exemplified by:

```
workers.each do |w|
  w.process(input, output) do |obj|
    raise ScoutException
    [Process.pid, obj.inspect] * " "
  end
end

assert_raise WorkerException do
  read.join
end
```
(From `test_process_exception`)  
If the supplied block raises, the worker wraps the exception and sends it out. The parent re-raises upon encountering a `WorkerException`, allowing test or application code to catch and handle it.

---

## API and Attributes

- **run**  
  Forks the child process and performs the supplied block. SIGINT is trapped for orderly exit.

- **process(input, output, &block)**  
  Reads objects from `input`, applies `block`, sends each output to `output` unless output is ignored, responds to `DoneProcessing` for shutdown, and sends errors as `WorkerException`.

- **abort**  
  Sends SIGINT, attempting to halt the worker.

- **join / .join(workers)**  
  Waits for this worker—or a group of workers—to finish, handling child process reaping robustly.

- **ignore_ouput**  
  When true (or if block returns `:ignore`), suppresses sending results to output.

- **worker_short_id**, **worker_id**  
  Aids in process tracking and debugging via unique composite identifiers, integrating process and queue membership.

---

## Edge Cases and Robustness

- **Mass Concurrency**: Tests verify reliable execution with hundreds of workers, atomic output, and resource cleanup.
- **Sequential and Collective Join**: Both per-worker and class-level batch joining are proven in tests.
- **Exception Propagation**: Exception handling through output streams and immediate test detection for any raised error.
- **Graceful Shutdown**: SIGINT trapping and explicit `DoneProcessing` signals ensure orderly process lifecycle management.

---

## Conclusion

`WorkQueue::Worker` embodies a rigorously tested, safe, and scalable approach to process-based parallelism in Ruby:  
- Launch and join hundreds of true OS processes.  
- Control inputs and outputs safely, including error signaling.  
- Rely on robust synchronization, resource management, and error relay—demonstrated exhaustively through real-world concurrency tests.  

This makes `WorkQueue::Worker` a reliable foundation for building flexible, high-performance concurrent Ruby systems.