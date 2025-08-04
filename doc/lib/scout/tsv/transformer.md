## Transformer: Advanced TSV Table Reshaping and Transformation

The `TSV::Transformer` class is a central mechanism for reshaping, converting, and streaming tabular data in the `TSV` framework. It supports conversion between all main TSV types (`:flat`, `:double`, `:single`, `:list`), flexible field and key control, and both mutation and transformation traversals.

### Initialization

A `TSV::Transformer` can be initialized with a `TSV::Parser`, a `TSV` object, or directly from a data source (filename, IO, etc). You may optionally supply a custom dumper (for output format and destination). If no dumper is provided, a compatible one is created automatically:

```ruby
trans = TSV::Transformer.new file
trans.key_field = "Key"
trans.fields = ["Values"]
trans.type = :flat
trans.sep = "\t"
```
(test_no_dumper_no_parser)

### Traversal and Transformation

The `traverse` method is the primary means to process and reshape data. It passes each key and value array to the given block, collecting and writing results via the dumper:

```ruby
trans = TSV::Transformer.new parser, dumper
dumper = trans.traverse do |k, values|
  [k, values.flatten]
end

tsv = trans.tsv
assert_equal %w(A1 A11 B1 B11), tsv['row1']
```
(test_traverse)

- `each` provides a variant intended for in-place mutation of values.
- You may also insert records directly: 
  ```ruby
  trans["row3"] = %w(A3 A33)
  ```

### Conversion Shortcuts

Transformers provide several shorthand methods for common structural conversions:

- **`to_list`**—Converts every value to a (named) list per record:
    ```ruby
    tsv = TSV.open(content)
    assert_equal "A1", tsv.to_list["row1"]["ValueA"]
    ```
    (test_to_list)
- **`to_single`**—Collapses multi-valued entries to a single value:
    ```ruby
    assert_equal "A2", tsv.to_single["row2"]
    ```
    (test_to_single)
- **`to_flat`**—Flattens values into a one-dimensional array per key:
    ```ruby
    assert_equal %w(A1 A11 B1 B11), tsv.to_flat["row1"]
    ```
    (test_to_flat)
- **`to_double`**—Expands to a "double" TSV (array of named arrays):
    ```ruby
    assert_equal %w(A1), tsv.to_double["row1"]["ValueA"]
    ```
    (test_to_double)

### Sampling

Use `head(max)` to obtain a TSV containing up to the first `max` rows:

```ruby
assert_equal ["row1", "row2"], tsv.head(2).keys
```
(test_head)

### Field and Metadata Management

You can change field layout, separator, and type dynamically:
```ruby
trans.key_field = "Key"
trans.fields = ["Values"]
trans.type = :flat
trans.sep = "\t"
```
- Metadata and filename tracking is preserved through transformation for provenance:
    ```ruby
    assert_include tsv.filename, File.dirname(file)
    ```
    (test_filename)

### Usage Patterns

- Ingest, apply mapping or structural change, and dump results to new TSV or file.
- Use when reorganizing scientific datasets across multiple structural conventions (flat ⇄ double etc).
- Efficient, stream-based pipeline segment for ETL workloads.

### Edge Behavior

- If no dumper or parser are provided, these are auto-initialized.
- Both `traverse` and `each` are available; the former is for transformation, the latter for in-place mutation.
- Blocks are passed key and value; return structure should match the destination type.
- Metadata (`key_field`, `fields`, etc) may be set before or after initialization.

---

For further concrete examples demonstrating traversal, mutation, and conversion methods, consult test cases in `test/scout/tsv/test_transformer.rb`, such as `test_traverse`, `test_to_list`, `test_to_double`, and `test_head`. These richly illustrate how to use the Transformer in practice, covering a range of data shapes and output options.