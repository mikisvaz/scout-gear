## TSV Dumper

The `TSV::Dumper` class is a robust and flexible tool for serializing tabular TSV data to streams, strings, or files, serving as a core part of the TSV pipeline for output and data interchange. It handles all details of formatting, header emission, and value representation, with particular attention to type handling (`:double`, `:single`, `:flat`, `:list`) and is designed for thread-safe, pipelined, and atomically-consistent output.

### Features

- **Header Generation:** Dumper can emit both preamble lines (including metadata) and field headers according to the TSV conventions. The header is fully configurable with options for key field, field names, separator, and can be suppressed or customized.
- **Thread-Safe Streaming:** All operations that write to the output stream are synchronized with a mutex for concurrently-safe outputs—vital for background jobs or parallel data pipelines.
- **Custom Stream Redirection:** The dumper's output can be dynamically redirected to any IO-like object (file, pipe, StringIO) via `set_stream`.
- **Flexible Value Encoding:** Fully supports TSV value types (`:double`, `:single`, `:list`, `:flat`), including explicit handling of array-of-arrays, value joining, and compact notation for sparse/missing values.
- **Error Signaling:** Dumper supports propagating exceptions across threads for robust, pipeline-friendly error handling.

### Test-derived Usage Patterns

#### Basic Dumper Creation & Output

```ruby
dumper = TSV::Dumper.new :key_field => "Key", :fields => %w(Field1 Field2), :type => :double
dumper.init
dumper.add "a", [["1", "11"], ["2", "22"]]
txt=<<-EOF
#: :type=:double
#Key\tField1\tField2
a\t1|11\t2|22
EOF
dumper.close
assert_equal txt, dumper.stream.read
```
- Instantiates the dumper with key-field and column info, initializes headers, adds a double-typed value, then validates output.

#### Custom IO Streams

You may pipe output to any IO-like object (such as `StringIO`):

```ruby
io = StringIO.new
dumper = TSV::Dumper.new :key_field => "Key", :fields => %w(Field1 Field2), :type => :double
dumper.set_stream io
dumper.init
dumper.add "a", [["1", "11"], ["2", "22"]]
# ... as above
io.rewind
assert_equal txt, io.read
```

#### Table Serialization

Direct serialization to string uses the dumper behind the scenes:

```ruby
tsv = TSV.setup({}, :key_field => "Key", :fields => %w(Field1 Field2), :type => :double)
tsv["a"] = [["1", "11"], ["2", "22"]]
assert_equal txt, tsv.to_s
```

#### Threaded and Exception-handling Output

Fault-tolerant serialization in background threads:

```ruby
dumper = TSV::Dumper.new :key_field => "Key", :fields => %w(Field1 Field2), :type => :double
dumper.init
t = Thread.new do
  dumper.add "a", [["1", "11"], ["2", "22"]]
  dumper.abort ScoutException
end
assert_raise ScoutException do
  TSV.open(dumper.stream, bar: true)
end
```
- Any exception in a background writer can be captured by the TSV loader reading from the dumper stream.

#### Sorted Keys Output

Deterministic output ordering is possible using the `keys` option:

```ruby
tsv["b"] = [["2", "22"], ["3", "33"]]
tsv["a"] = [["1", "11"], ["2", "22"]]
assert_equal txt, tsv.to_s(keys: tsv.keys.sort)
```

#### Compact Handling of Missing Values

Value compacting can suppress nils for sparse data:

```ruby
dumper = TSV::Dumper.new :key_field => "Key", :fields => %w(Field1 Field2), :type => :double, compact: true
# ...
assert_equal [], tsv["b"]["Field1"]

dumper = TSV::Dumper.new :key_field => "Key", :fields => %w(Field1 Field2), :type => :double, compact: false
# ...
assert_equal ["", ""], tsv["b"]["Field1"]
```
- Whether `compact` is `true` or `false` dictates how nil/empty subfields are handled in output serialization.

### Advanced Output and Integration

- The dumper integrates seamlessly into TSV’s streaming and `to_s` serialization, supporting both real-time and batch workflows.
- Metadata such as `filename` is carried along and accessible as part of the dumper's state and annotations, making it ideal for annotated persistence and further downstream processing.
- Supports writing to files directly via `write_file(file)`.

---

The TSV Dumper is a crucial, high-level utility for exporting, streaming, or persisting complex tabular data with type safety, concurrency robustness, and complete metadata annotation, as validated by extensive edge-case tests and real-world production applications.