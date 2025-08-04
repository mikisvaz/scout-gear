# TSV Indexing

The `TSV` module provides comprehensive, high-performance indexing mechanisms for tab-separated value data. Indexing is a cornerstone feature that enables rapid lookup, mapping, and reverse mapping between fields, value ranges, and positions within tabular datasets. This is critical for large data workflows, scientific informatics, and applications requiring fast subsetting or field resolution.

## Key Features

- **Field-to-field index mapping (`index`)**: Map values from one field (or multiple fields) to another field for efficient reverse lookups.  
- **Range-based interval indexing (`range_index`)**: Map numeric position ranges to the sets of entries (“which entry/row covers this position or interval?”).  
- **Position-based point lookups (`pos_index`)**: Quickly resolve which entries match a specific coordinate or position value.
- **Persistence support**: Store indexes on disk (TokyoCabinet-backed or similar), enabling speedups in repeated or batch queries.
- **Flexible configuration**: Works on files, IO streams, TSV objects, supports selective fields, multi-key mapping, and dynamic selection.

## Basic Usage and Behaviors

### 1. Direct Field Index (`TSV.index` and `#index`)

Create an index that maps from the target field's values (in any record) to the original key(s). Available as both a class and instance method, with consistent options. 

#### Example: Reverse Indexing a Double TSV

Suppose a TSV file with several multi-valued columns:

```
#: :sep=/\s+/#:type=:double#:merge=:concat
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3|a
row2    a    b    id3
```

You can create a reverse index by a target “ValueB” column:

```ruby
index = TSV.index(filename, :target => "ValueB")
# index["row1"] => 'b'
# index["a"]    => 'b'
# index["aaa"]  => 'b'
# index["A"]    => 'B'
```

Limit the index to map through another field:

```ruby
index = TSV.index(filename, :target => "ValueB", :fields => ["OtherID"])
# index["a"]    => 'B'
# index["B"]    => nil
```

From a `TSV` instance in memory (or open IO):

```ruby
tsv = TSV.open(filename)
index = tsv.index(:target => "ValueB", :fields => "OtherID")
# index["a"] => 'B'
```

Use persistence to speed up repeat queries:

```ruby
index = TSV.index(filename, :target => "ValueB", :persist => true)
```

#### Metadata and Field Handling

- Field and key names are propagated to the index result:
  ```ruby
  assert_equal "OtherID", index.fields.first
  assert_equal "Id", index.key_field
  ```
- If you do not specify `:fields`, all are indexed by default.
- Order is preserved unless `:order => false` is set.

#### Edge Cases

- Nonexistent lookup keys return `nil`.
- The index result is read-only and must be rebuilt if the underlying TSV changes.

### 2. Range Index (`TSV.range_index` and `#range_index`)

Useful for genomic or interval data: quickly query “which rows cover this position or range?”

**Example:**

Given TSV data representing intervals (“Start” and “End” fields):

```
#ID:Range
a:   ______
b: ______
...
```
After parsing and extracting the "Start" and "End" fields:

```ruby
f = tsv.range_index("Start", "End", :persist => true)
# f[0].sort         => []
# f[1].sort         => ["b"]
# f[(3..4)].sort    => ["a", "b", "c", "d", "e"]
# f[20].sort        => []
```

- Accepts queries as numeric positions or Ruby `Range`.
- The backing store is optimized and can be persisted for repeated fast queries.
- Handles conversion of string positions, field arrays, and supports large data.

### 3. Position Index (`TSV.pos_index` and `#pos_index`)

Look up keys by matches to a specific position field (e.g., single-point genomic loci).

```ruby
f = tsv.pos_index("Start", :persist => true)
# f[0].sort      => []
# f[(2..4)].sort => ["a", "c", "d", "e"]
```

- Accepts integer or range queries for rapid location lookups.

### 4. Indexing from Flat and Double TSVs

Both flat (one/many-to-many) and double (matrix-style) TSVs are supported for indexing:

```ruby
index = TSV.index(filename, :target => "Id")
# index["aa"] => "row1"
```

## Advanced Features and Integration

- **Instance/functional parity**: All main methods are available as instance methods so you can write `tsv.index(...)` or `TSV.index(tsv, ...)`.
- **Custom selection and filtering**: The `:fields` argument (Array, nil, :all) and fine-grained selection logic are supported.
- **Bar/progress reporting**: Enable analytics or debugging by passing `bar: true`.

## Persistence, Caching, and Diagnostics

- Use `:persist => true` for expensive or repetitively accessed indexes.
- After updating data, you should clear caches or persist stores before rebuilding indexes to avoid staleness.
- Field/column names are mirrored from the source, aiding further joins or program introspection.

## Edge Case Handling

- Indexes handle missing values, overlapping intervals, and complex field structures robustly, as exemplified in the extensive test coverage.
- For missing, nil, or unmatched query inputs, the API returns `nil` or empty sets/arrays.

## Limitations & Notes

- Indexes are read-only—rebuild the index after TSV data changes.
- In multivalued, overlapping, or sparsely keyed datasets, validate index output for correctness in application context.

## Summary

TSV’s indexing API abstracts field, range, and point queries into fast, declarative Ruby methods. Whether you’re mapping identifiers, looking up genomic intervals, or building rapid memoization schemas over tabular records, the API offers both the flexibility and the speed needed for demanding scientific and engineering data applications.

See the above code snippets (taken directly from the test suite) for concrete usage patterns and edge-case demonstrations. For more, see the [Core Module Overview](#core-module-overview-and-annotation-system) and related TSV documentation.