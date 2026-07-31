# Running Parallel Work

This document explains how to distribute computation across multiple
processes using the WorkQueue system.

It is intended for workflow authors who need to parallelize data
processing or task execution.

## What problem does this solve?

Ruby has a Global Interpreter Lock (GIL), so threads don't provide true
CPU parallelism. To use multiple cores, you need multiple processes. But
managing process pools, distributing work, collecting results, and handling
errors across processes is complex.

The WorkQueue system provides a simple abstraction for multi-process
parallelism:

- Fork N worker processes.
- Feed work items to the queue.
- Workers process items and return results.
- Results are collected in the main process.

It integrates seamlessly with TSV traversal and workflow execution.

## When do I use it?

- When processing large TSV datasets and want to use multiple cores.
- When running multiple independent tasks in parallel.
- When you need CPU parallelism that threads can't provide.

## Using WorkQueue with TSV traversal

The simplest way to parallelize work is through `TSV.traverse` with the
`cpus:` option:

```ruby
result = tsv.traverse(:key, into: :tsv, cpus: 4) do |key, values|
  [key, expensive_compute(values)]
end
```

This automatically:
1. Forks 4 worker processes.
2. Distributes rows across the workers.
3. Collects results into a new TSV.

The block must be serializable (Marshal-compatible) because it's sent to
worker processes via IPC sockets.

## Using WorkQueue directly

For more control, use WorkQueue directly:

```ruby
require 'scout/work_queue'

wq = WorkQueue.new(num_workers: 4)

# Queue work items
wq.add_inputs([1, 2, 3, 4, 5])

# Process in workers
wq.process do |item|
  item ** 2
end

# Collect results via callback
results = []
wq.callback do |result|
  results << result
end

wq.run
# results = [1, 4, 9, 16, 25]
```

### WorkQueue lifecycle

1. **Create**: `WorkQueue.new(num_workers: N)` — Creates the queue but
   doesn't start workers yet.
2. **Add inputs**: `wq.add_inputs(collection)` — Queue items for
   processing. Can be called multiple times.
3. **Process**: `wq.process { |item| ... }` — Define the worker block.
4. **Callback**: `wq.callback { |result| ... }` — Define result handling.
5. **Run**: `wq.run` — Fork workers, process all inputs, collect results,
   and join.

### Streaming inputs

WorkQueue can read from a streaming source instead of a fixed array:

```ruby
wq = WorkQueue.new(num_workers: 4)
wq.add_inputs(reader_stream)
wq.process { |line| process_line(line) }
wq.callback { |result| write_result(result) }
wq.run
```

The queue reads items lazily from the stream, so memory usage stays low
even for very large inputs.

## Synchronizing concurrent access

When multiple processes need access to shared resources (like a database
or file), use a Semaphore:

```ruby
require 'scout/semaphore'

Semaphore.sync("my_resource") do
  # Only one process at a time can execute this block
  database_write(data)
end
```

Semaphores use file-based locking with C extensions (via RubyInline) for
efficiency. If the C compiler is unavailable, semaphore operations become
no-ops (they don't block), so ensure the C toolchain is available in
production.

## Common mistakes

- **Non-serializable blocks**: The worker block and captured variables
  must be Marshal-serializable. Avoid Procs, file handles, IO objects,
  Thread objects, and other non-serializable types.
-- **Expecting thread-like behavior**: WorkQueue uses processes, not
  threads. State is not shared between workers. Each worker gets its own
  copy of memory (via fork).
- **Not closing streams**: If you use streaming inputs or callbacks that
  write to streams, make sure the streams are properly closed after
  `wq.run` completes.
- **Assuming Semaphore works without a C compiler**: Semaphore relies on
  C extensions. Without them, it silently becomes a no-op. Verify that
  RubyInline can compile.
- **Forgetting to call `.run`**: The WorkQueue doesn't start processing
  until you call `.run`. Adding inputs and defining blocks doesn't execute
  anything.

## See also

- [scout-essentials: Handling Streams](https://github.com/mikisvaz/scout-essentials/blob/main/doc/user/HandlingStreams.md)
- [Processing Tabular Data](ProcessingTabularData.md)
- [Caching Data](CachingData.md)
- [Cookbook](Cookbook.md)
