# TSV Utility Functions

The TSV utility module supplies a comprehensive collection of advanced manipulation, querying, and inspection functions for TSV tables, critical for complex data wrangling tasks. It integrates tightly with annotation, streaming, persistence, and key/field manipulation patterns found in scientific and bioinformatic workflows.

---

## Overview

`lib/scout/tsv/util.rb` extends the TSV object with important capabilities, including:

- Filtering rows by fields or keys, often with persistent backing for reusability (see [tsv/util/filter.rb](#))
- Processing and transforming field values in place or across the table ([tsv/util/process.rb](#))
- Selecting and subsetting (rows, columns, or values) flexibly ([tsv/util/select.rb](#))
- Reordering, slicing, and transposing table layouts ([tsv/util/reorder.rb](#))
- Unzipping and splitting complex fields or replicates ([tsv/util/unzip.rb](#))
- Sorting, ranking, and pagination ([tsv/util/sort.rb](#))
- Melting wide tables into "long" formats for statistical analysis ([tsv/util/melt.rb](#))

---

## Field Discovery and Table Inspection

### Field Matching and Identification

- Rapid resolution of column headers or indices for dynamic field access, even in loosely formatted tables.

  Example (from internals and external use):
  ```ruby
  field_pos = identify_field(field)
  ```
  Resolves the numerical position of a named field or key.

- Aggregates all fields (including key) for reporting or downstream workflows:
  ```ruby
  all_fields = tsv.all_fields # => ["Key", "Field1", "Field2", ...]
  ```

### Summarization

Generate a friendly, multi-line summary of table properties with `summary`. Includes file name, key field, headers, type, size, namespace, identifiers, and an example row. Used to quickly inspect a dataset interactively.

---

## Annotated Data Access Patterns

- By default, `tsv[key]` yields a `NamedArray` annotated with field names and the row key, unless using `unnamed` mode or a `:flat` structure. This enhances downstream code for readability and correctness.

- Iterators such as `each` and `collect` accept blocks over keys and (possibly annotated) values, and will auto-setup named arrays unless disabled.

  Test-driven examples:
  ```ruby
  tsv.unnamed = false
  assert NamedArray === tsv.collect{|k,v| v }.first
  assert "row1", tsv["row1"].key
  ```

- Unnamed mode disables field-name annotation for speed:
  ```ruby
  tsv.unnamed = true
  refute NamedArray === tsv.collect{|k,v| v }.first
  ```

---

## Table Combination and Maintenance

- `merge(other)` merges entries from another TSV into the current table, preserving annotation and metadata.
- `merge_zip(other)` performs an in-place "zipped" merge of values on matching keys, useful for combining parallel datasets.

- Temporary in-place update:
  ```ruby
  tsv.with_unnamed(true) { ... }
  ```
  Allows fast operations without annotation overhead.

---

## File- or Field-Oriented Utilities

- **Counting value matches in fields:**  
  The `.field_match_counts(file, values, options={})` efficiently counts how many times each queried value appears in the table, field-wise, using fast grep and intermediate files when scaling to large data.

---

## Identity and Diagnostics

- Concise fingerprinting and digest methods (`fingerprint`, `digest_str`) help uniquely summarize or identify the table's structure and content for comparisons, debugging, or caching.

---

## Edge Cases and Robustness

- All utility methods explicitly honor the table's `@unnamed` flag and data type, ensuring correct behavior for headerless, single-field, flat, double, and all persistent table types.
- Utilities work interchangeably on TSV objects and generic Ruby hashes or file streams, wherever appropriate.

---

## Related Submodules

For specialized data manipulation, see:

- [Row Filtering](tsv/util/filter.rb)
- [Field Processing](tsv/util/process.rb)
- [Row/Col Selection](tsv/util/select.rb)
- [Reordering, Slicing, and Transposing](tsv/util/reorder.rb)
- [Unzipping and Replicate Handling](tsv/util/unzip.rb)
- [Sorting and Pagination](tsv/util/sort.rb)
- [Melting (Wide to Long format)](tsv/util/melt.rb)

---

## Further Reading and Testing

- Core [TSV module reference](tsv.md)
- Test suite (see [test/scout/tsv/test_util.rb](test/scout/tsv/test_util.rb)) shows integration with persistence, field management, and annotation modes.
- Examples and diagnostics for troubleshooting annotation, field matching, or edge-case behaviors. 

---

TSV utility functions empower you to efficiently analyze, mutate, reformat, and summarize tabular data structures, providing the backbone for scientific Ruby data analysis with annotation, speed, and flexibility.