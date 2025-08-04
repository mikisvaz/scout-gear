## Stream API: TSV Streaming and Concatenation

The `TSV::Stream` submodule provides advanced tools for streaming, merging, and pasting tabular data from multiple sources, especially when datasets are too large for memory or need to be combined efficiently in parallel processing pipelines.

### Features

- **Stream Pasting** – Merge ("paste") multiple tabular/TSV streams horizontally by key, yielding rows with all combined fields. Handles missing data, field prefixes, different field headers, sorted/unsorted data, with full metadata tracking.
- **Stream Concatenation** – Concatenate multiple TSV streams vertically (row-wise), merging rows when keys overlap and preserving multiple values as arrays.
- **Format-Aware** – Fully aware of header lines, field orders, separators, and TSV types (`:list`, `:double`, `:flat`, etc.), able to accommodate source streams of differing structure.
- **Gap Filling & Robustness** – Where data is missing in any joined stream for a given key, empty fields are inserted to preserve table shape, ensuring robust downstream access.
- **Sorting Support** – Optionally sorts all input streams by key prior to merging, ensuring alignment even if incoming data order differs.
- **Parallel-Ready** – Streaming and threading support is robust and allows concurrent or out-of-core manipulation of extremely large tabular files or IO sources.

### Usage and Code Examples

#### Pasting Multiple Streams

Combine several TSV-formatted streams by key, collecting and aligning their fields:

```ruby
s1 = StringIO.new text1
s2 = StringIO.new text2
s3 = StringIO.new text3
tsv = TSV.open TSV.paste_streams([s1,s2,s3], :sep => " ", :type => :list)
assert_equal ["A", "B", "C", "a", "b", "c"], tsv["row1"]
assert_equal ["AA", "BB", "CC", "aa", "bb", "cc"], tsv["row2"]
assert_equal ["AAA", "BBB", "CCC", "aaa", "bbb", "ccc"], tsv["row3"]
```
Supports automatic header determination, field alignment even across missing data, and custom separators.

#### Handling Sorting and Irregular Key Orders

Sorted stream merges guarantee result row order and match columns by key, not by appearance:

```ruby
tsv = TSV.open TSV.paste_streams([s1,s2,s3], :sep => " ", :type => :list, :sort => true)
assert_equal "Row", tsv.key_field
assert_equal %w(LabelA LabelB LabelC Labela Labelb Labelc), tsv.fields
```

#### Graceful Handling of Missing Data

When some streams do not provide rows for certain keys, missing values are filled with `""`:

```ruby
assert_equal ["A", "B", "C", "", "", ""], tsv["row1"]
assert_equal ["AA", "BB", "CC", "aa", "bb", "cc"], tsv["row2"]
assert_equal ["", "", "", "", "", "ccc"], tsv["row3"]
```

#### Same-Field Stream Joining

Supports combining multiple streams that share the same field names, preserving duplicate values as arrays (double-type table):

```ruby
tsv = TSV.open TSV.paste_streams([s1,s2], :sep => " ", :type => :double, :sort => false, :same_fields => true)
assert_equal ["AA", "AAA"], tsv["row2"][0]
```

#### Headerless Streams

Pasting TSVs without headers (no `#` line) is fully supported:

```ruby
tsv = TSV.open TSV.paste_streams([s1, s2], :type => :double, :sort => false, :same_fields => true)
assert_equal ["AA", "AAA"], tsv["row2"][0]
```

#### Concatenating Multiple Streams

Combine multiple streams vertically (all rows from all sources):

```ruby
tsv = TSV.open TSV.concat_streams([s1,s2]), :merge => true
assert_equal ["A"], tsv["row1"][0]
assert_equal ["AA","BB"], tsv["row2"][0]
assert_equal ["AAA"], tsv["row3"][0]
```
Works for any number of streams.

#### Flexible Data Types

Supports all base TSV types (`:flat`, `:list`, `:double`), including automatic value expansion:

```ruby
tsv = TSV.open TSV.paste_streams([s1,s2], :sep => " ", :type => :double)
assert_include tsv["row1"], %w(f1 f2 f3)
```

#### Advanced Case: Non-One-to-One and Repeated Keys

When multiple rows in a stream share keys, the `one2one: false` option enables array expansion for all values:

```ruby
tsv = TSV.open(TSV.paste_streams([s1,s2], sort:true, one2one: false), merge: true, one2one: false)
assert_equal 2, tsv["YHR055C"][0].length
assert_equal %w(SGV1) * 3, tsv["YPR161C"][2]
```

### Edge Case Handling and Robustness

- Handles streams of different lengths, missing rows, header-only streams, and format inconsistencies gracefully.
- All exceptions during stream processing are trapped, logged, and streams are closed or canceled explicitly.
- Results are always thread-safe, suitable for downstream TSV.open parsing, and support further chaining in workflow pipelines.

---

These streaming utilities enable scalable tabular data ETL and multi-source aggregation workflows in scientific, data engineering, and analytics environments. All behaviors, including header decoding, alignment, and error tolerance, are fully exercised in the accompanying comprehensive test suite.