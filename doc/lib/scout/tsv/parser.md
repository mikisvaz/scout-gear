# TSV Parser

The `TSV::Parser` module powers all TSV data ingestion in the Scout ecosystem by delivering a rich, robust, and highly flexible parsing machinery for tabular data. It enables fine-grained extraction of headers, keys, fields, and row values from files, strings, or IO streams, pairing seamless field/key remapping and type conversion with efficient, streaming, and persistent workflows. This submodule is the backbone of schema inference, value type normalization, advanced streaming, and parser-driven table transformation.

---

## Features

- **Line and Stream Parsing**: Parse a single line or process entire TSV files/streams, using flexible key, field, and type selection.
- **Header and Metadata Extraction**: Reads and interprets headers, options, field names, key columns, separators, and annotation lines.
- **Support for All TSV Structures**: Handles all core TSV types (`:single`, `:list`, `:double`, `:flat`) and arbitrary custom table layouts.
- **Flexible Field and Key Specification**: Supports field selection/reordering and key remapping by name or position.
- **Automatic Type Casting**: Cast string values using Ruby built-ins (`:to_i`, `:to_f`) or custom blocks.
- **Row Filtering / Grep**: Supports filtering input by custom logic (`select`), grep, or tsv_grep (by value or regex).
- **Persistent Backend Integration**: Loads directly into persistent data stores if compatible, leveraging backend serializers and types.
- **Direct-to-Database Streaming**: Efficient, direct loading to persistent tables for large, memory- or IO-bound datasets.
- **Custom Row Fixing**: Accepts per-line preprocessing proc for advanced or nonstandard row handling.
- **Block API**: All key parsing functions can yield directly for streaming, reducing memory use.
- **Merging Duplicate Keys**: Flexible merge and concat strategies for dealing with duplicate data.
- **Resilient Edge Case Handling**: Robust in the face of missing headers, partial tables, custom field/indexing schemes, IO errors, and concurrency.

---

## Test-Driven Usage Patterns and Idioms

### Parsing Individual Lines

Extract the key and values from a single TSV line, optionally picking columns or applying conversions:

```ruby
line = (0..10).to_a * "\t"
key, values = TSV.parse_line(line)
assert_equal "0", key
assert_equal (1..10).collect{|v| v.to_s }, values

key, values = TSV.parse_line(line, key: 2)
assert_equal "2", key
assert_equal %w(0 1 3 4 5 6 7 8 9 10), values
```

### Double and Flat TSV Types with Casting

Convert list-of-lists columns, applying type conversions:

```ruby
line = (0..10).collect{|v| v == 0 ? v : [v,v] * "|" } * "\t"
key, values = TSV.parse_line(line, type: :double, cast: :to_i)
assert_equal "0", key
assert_equal (1..10).collect{|v| [v,v] }, values
```

### Stream Parsing and Row Processing

Efficiently parse line-by-line from an in-memory or file-backed stream, with or without a block:

```ruby
lines =<<-EOF
1 2 3 4 5
11 12 13 14 15
EOF
lines = StringIO.new lines

data = TSV.parse_stream lines, sep: " "
assert_equal data["1"], %w(2 3 4 5)

sum = 0
TSV.parse_stream(lines, sep: " ") do |k, values|
  sum += values.inject(0){|acc,i| acc += i.to_i }
end
assert_equal 68, sum
```

### Header Parsing and Metadata Extraction

Discern key fields and parsing options from a header:

```ruby
header =<<-EOF
#: :sep=" "
#Key ValueA ValueB
k A B
EOF
header = StringIO.new header

assert_equal "Key", TSV.parse_header(header)[1]
```

### Field and Key Remapping (By Name or Position)

Parse and select custom fields, or invert keys:

```ruby
tsv = TSV.parse(content, fields: %w(ValueB))
assert_equal [%w(b B)], tsv['k']
assert_equal %w(ValueB), tsv.fields

tsv = TSV.parse(content, key_field: "ValueB")
assert_equal %w(b B), tsv.keys
assert_equal %w(a A), tsv["B"][1]
```

### Limiting Rows with :head

Process a fixed number of rows:

```ruby
tsv = TSV.parse(content, :head => 2)
assert_equal 2, tsv.keys.length
```

### Grep Filtering and Select

Parse only rows matching certain keys, patterns, or values:

```ruby
tsv = TSV.parse(content, :tsv_grep => ["k3","k4"])
assert_equal %w(k3 k4), tsv.keys.sort
```

### Streaming to Persistent Storage

Load parsed TSV data directly into a persistent backend, casting on-the-fly:

```ruby
TmpFile.with_file do |db|
  data = ScoutCabinet.open db, true, "HDB"
  TSV.parse content, sep: " ", header_hash: '', data: data, cast: :to_i, type: :list
  assert_equal [1, 2], data["k"]
end

TmpFile.with_file do |db|
  content.rewind
  data = ScoutCabinet.open db, true, "HDB"
  TSV.parse content, sep: " ", header_hash: '', data: data, cast: :to_i, type: :list, serializer: :float_array
  assert_equal [1.0, 2.0], data["k"]
end
```

### One-to-One Relationship and Merge Handling

Synchronize keys and values, or accumulate/merge duplicate entries as needed:

```ruby
tsv = TSV.open(filename, key_field: ..., fields: [...], merge: true, one2one: true, type: :double)
assert_equal 16, tsv["NR1H3"]["Sign"].length
```

### Parser Class — Reusable Streaming Parse

Leverage the parser for multiple passes or advanced field manipulations:

```ruby
parser = TSV::Parser.new content, sep: " ", header_hash: ''
assert_equal "Key", parser.key_field

values = []
parser.traverse fields: %w(ValueB), type: :double do |k,v|
  values << [k,v]
end
assert_equal [["k", [%w(b B)]]], values
```

Remap key/fields on-the-fly:

```ruby
parser.traverse key_field: "ValueA", fields: :all, type: :double do |k,v|
  values << v
end
assert_include values.flatten, 'a'
```

### Direct-to-Persistence Load Optimization

If the value type, key structure, and storage support it, stream loading is performed efficiently, including log reporting:

```ruby
TmpFile.with_file do |tmp_logfile|
  old_logfile = Log.logfile
  Log.logfile(tmp_logfile)
  TmpFile.with_file do |persistence|
    data = ScoutCabinet.open persistence, true
    tsv = Log.with_severity(0) do
      TSV.parse(content, data: data)
    end
    assert_equal %w(b B), tsv["k"]["ValueB"]
    assert_equal %w(a A), tsv["k4"]["ValueA"]
  end
  Log.logfile(old_logfile)
  assert Open.read(tmp_logfile).include?("directly into")
end
```

### Determining Supported Parse Options

Introspect and adapt to all legal parser options:

```ruby
assert_include TSV.acceptable_parser_options, :namespace
```

---

## Robust Edge Case Handling

- **Headerless Tables**: Operates correctly whether headers are present or lines start data directly.
- **Flexible Key/Field Indexing**: Recognizes fields by name or number interchangeably, tolerant of nils and missing fields.
- **Partial Rows and Custom Separators**: Parses rows even with variable columns or nonstandard separators.
- **Custom Fix Blocks**: Users can pass lambdas to preprocess every row before parse.
- **Persistent Data Safety**: Auto-detects and adopts correct serializer, type, and merge strategies when loading into database-backed hashes.
- **Safe Stream Handling**: Catches and surfaces stream exceptions or IO failures, attempts graceful aborts where possible.

---

## API Reference

- `TSV.parse_line(line, ...)` — Single row to key, values (with key/field/cast/type controls)
- `TSV.parse_stream(io_or_enum, ...)` — Parse multiple rows from stream, with block and merge controls
- `TSV.parse_header(io, ...)` — Extract parse options, fields, and metadata from a header
- `TSV.parse(io_or_parser, ...)` — High-level end-to-end TSV parsing
- `TSV::Parser.new(io_or_file, ...)` — Build a parser for repeated traversals, dynamic remapping, and fine-tuned reading
- `TSV.acceptable_parser_options` — Symbol list of all parse-time keyword options accepted

---

## Design and Integration Notes

- The parser is used internally by `TSV.open`, `TSV.traverse`, and can be safely reused for multi-pass or multi-index scans across large files.
- Supports stream objects, files, arrays, in-memory strings, and already-initialized parser objects.
- Robustly interacts with persistent backends (e.g., TokyoCabinet), advanced identifier annotation workflows, and dumper/transformer streaming.
- All methods are fully compatible with parallel/traversal and attach workflows.

---

The `TSV::Parser` submodule provides tested, production-grade parsing for scientific tabular data, powering fast, repeatable, and flexible workflows for both structured file ingestion and memory-efficient, large-scale data mining. All behavior and idioms described here are directly valdiated by comprehensive tests, spanning a wide variety of TSV use cases and file formats.