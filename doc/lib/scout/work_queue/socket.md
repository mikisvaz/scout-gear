## WorkQueue Socket

This section documents the core socket abstraction used by `WorkQueue` for robust inter-process communication between the queue manager and its forked workers. The `WorkQueue::Socket` class provides reliable object serialization, transmission, and stream lifecycle management, as well as safe concurrent access and error signaling.

### Key Features

- **Custom Serialization:** By default, uses `Marshal` to encode and decode Ruby objects for transmission.
- **Type-Aware Protocol:** Efficiently distinguishes integers, strings, nil (as null), annotated objects, and general Ruby objects for correct round-tripping.
- **Semaphore-Based Synchronization:** Employs `ScoutSemaphore` to safely coordinate concurrent `read` and `write` access across threads or processes, avoiding races.
- **Stream Control:** Cleanly handles closing of read and write streams and signals end-of-stream via sentinel objects.

### Basic Usage and Behaviors

#### Writing and Reading Objects

Objects are written to the socket and can be of any Ruby-serializable type:

```ruby
socket = WorkQueue::Socket.new 

socket.write 1
socket.write 2
socket.write "STRING"
socket.write :string

assert_equal 1, socket.read
assert_equal 2, socket.read
assert_equal "STRING", socket.read
assert_equal :string, socket.read
```

The socket write/read protocol ensures that all objects are read back in the same order and type, making the sockets suitable for marshalling arbitrary payloads between processes.

#### Signaling Stream Termination

Streams are closed using `close_write`. After this, attempting to read causes a `ClosedStream` exception to be raised, which is used throughout `WorkQueue` to detect end-of-stream and cleanly terminate looping readers.

```ruby
socket.close_write
assert_raise ClosedStream do
  socket.read
end
```

This explicit end-of-stream signaling underpins robust shutdown across process boundaries and ensures the parent process won't deadlock on a worker that has finished sending.

#### Synchronization and Safety

All reads and writes are wrapped in named semaphores to prevent concurrent access anomalies. These semaphores use process-unique keys for isolation:

- Each `Socket` instance creates `@write_sem` and `@read_sem`, released and acquired as needed.
- Cleanup of semaphores is automatic on `clean`.

#### Object Serialization Details

- `nil` is sent with a "N" header and zero payload.
- Integers have a specialized "I" header.
- Strings and annotated objects are handled with "C" and "S" headers, respectively. All other objects fall back to the "S" protocol, relying on `Marshal`.

### Error Propagation and Aborting

If a fatal error occurs (for example, in a worker process), the `abort(exception)` method records the error and forcefully closes the output side. Readers in the parent can then respond to this, using the socket’s `exception` property to raise the original error if needed.

### Resource Management

Sockets are cleaned up either explicitly with `clean` or at the end of their lifecycle, ensuring:

- File descriptors for both ends of the stream are closed.
- Underlying semaphores are destroyed to avoid resource leakage.

### Performance

A bulk test (`__test_speed`) demonstrates the ability of the socket to handle tens of thousands of messages efficiently:

```ruby
Thread.new do
  num.times do |i|
    socket.write nil
  end
  socket.write DoneProcessing.new 
end

while true
  i = socket.read
  break if DoneProcessing === i
end
```

This validates that the protocol can handle high message rates required in large-scale job queues.

### Summary

- The `WorkQueue::Socket` abstraction provides thread-safe, signal-rich, and robust Ruby object pipeline communication between forking processes.
- End-of-stream, error, and abort signaling are explicit and support high reliability.
- Backed by clear, readable tests, the socket layer is foundational to `WorkQueue`'s resilience under concurrency, stream closure, and error conditions.