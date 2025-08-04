## TSV Open, Streams, and Traversal

TSV's "open", stream, and traversal facilities (centered in `tsv/open.rb`) provide high-performance, parallelizable data processing over IO, files, TSVs, arrays, and streams, with robust error handling and destination flexibility. The core function, `TSV.traverse` (delegating to `Open.traverse`), creates a unified, highly flexible interface for streaming records—potentially in parallel—into a wide array of collection or output types. All patterns below are confirmed by extensive test coverage.

---

### Parallel and Sequential Traversal with `TSV.traverse`

`TSV.traverse` enables you to process data—such as lines from an Array, Hash, TSV, IO, or stream—with optional (and scalable) parallelization. The `:cpus` option specifies the number of workers; `:into` sets the destination type for results. Supported destinations include arrays, sets, hashes, TSVs, IO handles, specialized Dumper objects, or a pipe/stream.  

**Parallel Array Traversal:**

```ruby
r = TSV.traverse lines, :into => [], :cpus => 2 do |l|
  l + "-" + Process.pid.to_s
end

assert_equal num_lines, r.length
assert_equal 2, r.collect{|l| l.split("-").last}.uniq.length
```
Here, 1000 items are processed using two OS-level processes, and the results are gathered into an array. Unique process ids confirm parallel execution.

**Stream as Destination:**  
To process in parallel and stream results (for downstream or pipeline processing):

```ruby
r = TSV.traverse lines, :into => :stream do |l|
  l + "-" + Process.pid.to_s
end

assert_equal num_lines, r.read.split("\n").length
```

**File Output by Path:**  
Output can be automatically directed to a file via a `Path` object:

```ruby
Path.setup(tmpfile)
io = TSV.traverse array, :into => tmpfile do |e|
  e
end
io.join
assert_equal size, Open.read(tmpfile).split("\n").length
```

---

### Exception and Robust Error Handling

Any uncaught error in a worker is propagated through the output stream or dumper. For example:

```ruby
assert_raise ScoutException do
  r = TSV.traverse lines, :into => :stream, cpus: 3 do |l|
    raise ScoutException if i > 10
    i += 1
    l + "-" + Process.pid.to_s
  end
  r.read
end
```
Similar handling propagates exceptions for Dumpers and other destinations.

---

### Input Source Flexibility

`TSV.traverse` works for:  
- TSV and Hash objects (`|key, value|`)
- Arrays/enumerables (elements yielded)
- IO/StringIO/File (line by line, or parsed values)
- Priority queues (e.g., `FastContainers::PriorityQueue`)
- `Step` objects (e.g., for asynchronous pipelines)
- `TSV::Parser` instances

This polytypism ensures TSV can serve as a universal infrastructure for tabular or linewise data.

---

### Advanced Streaming, "Line" Mode, and Collapsing

**Line-based Traversal:**  
Set `:type => :line` to yield file/IO lines directly (not parsed):

```ruby
lines = Open.traverse file, :type => :line, :into => [] do |line|
  line
end
assert_include lines, "row2 AA BB CC"
```

**Collapsing Streams:**  
TSV supports streaming collapse of duplicate keys. Example from tests:

```ruby
s = StringIO.new text
collapsed = TSV.collapse_stream(s)
tsv = TSV.open collapsed 
assert_equal ["A", "a"], tsv["row1"][0]
assert_equal ["BB", "bb"], tsv["row2"][1]
```
Here, all occurrences of "row1" or "row2" are collapsed so values are aggregated per key.

---

### Specialized Features and Examples

- **Priority Queue Traversal:**
  ```ruby
  queue = FastContainers::PriorityQueue.new(:min)
  array = []
  100.times do e = rand(1000).to_i; array << e; queue.push(e,e) end
  res = Open.traverse queue, :into => [] do |v|
    v
  end
  assert_equal array.sort, res
  ```
- **Step Traversal for Pipelines:**
  ```ruby
  step = Step.new tmpdir.step[__method__] do
    lines = size.times.collect{|i| "line-#{i}" }
    Open.traverse lines, :type => :array, :into => :stream, :cpus => 3 do |line|
      line.reverse
    end
  end
  step.type = :array
  assert_equal size, step.run.length
  ```
- **Header/Field Index Traversal:**  
  Custom traversals with explicit `key_field` & `fields`:
  ```ruby
  k, f = Open.traverse TSV.open(tmp), key_field: "Y", fields: ["X"] do end
  assert_equal "Y", k
  ```

---

### Progress Bars, Thread Management, and Robustness

- The `:bar` option enables on-the-fly progress display.
- Thread and stream cleanup is robust. If exceptions occur, all internal queues, threads, and resources are properly finalized.
- You can specify `:keep_open` for manual stream closure.

---

## Summary

TSV's open, stream, and traverse mechanisms allow fast, safe, flexible, and parallel data pipelining across Ruby collections, files, and TSV objects. Destinations are fully configurable, errors and resource cleanup are robust, and complex workflows—such as priority queues or pipeline steps—are natively supported. All patterns are directly validated against high-coverage tests to ensure reliability in large-scale scientific or data-processing contexts.