# TSV Module - CSV Integration

## Overview

The `TSV.csv` method enables seamless integration of CSV-formatted data into the TSV module's robust tabular framework. This facility empowers users to read and convert CSV content (from strings, files, IOs, Path objects, or remote resources) into rich TSV structures that take advantage of field-aware lookups, custom indexing, flexible type settings, and TSV's annotation/features stack.

The method supports both headered and headerless CSV formats, dynamic or explicit field/key designation, merging, and casting, mirroring the ergonomics of TSV handling to CSV-origin data.

## Main Features

- Accepts diverse CSV sources: strings (inline or file path), IO, Path, and remote files.
- Grammar control of headered/headerless data via `:headers` option.
- Explicit control over TSV key field and value structure (`:key_field`, `:fields`, `:type`, `:merge`).
- Smooth automatic adjustment to TSV's semantical types (`:single`, `:double`, `:list`, or `:flat`).
- Support for per-value casting via `:cast`.
- Robust field and key reordering, with default merging behavior as needed.

## Usage and Examples

### Standard CSV Import with Headers

By default, CSV input with headers in the first row turns into a TSV keyed on the first column:

```ruby
text =<<-EOF
Key,FieldA,FieldB
k1,a,b
k2,aa,bb
EOF

tsv = TSV.csv(text)
assert_equal 'bb', tsv['k2']['FieldB']
```

Result: The TSV object has keys from the "Key" column and hash-like access to each row's field values.

### Specific Key Field and TSV Type

You can specify which field should function as the key, as well as the internal TSV value structure (default is `:list`, but others are supported):

```ruby
tsv = TSV.csv(text, :key_field => 'FieldA', :type => :list)
assert_equal 'bb', tsv['aa']['FieldB']
```

Here, `FieldA` governs the keys, allowing direct access to rows by that value.

### Double Value Mapping

The double (`:double`) type ensures all values are collected as arrays, even with a single entry:

```ruby
tsv = TSV.csv(text, :key_field => 'FieldA', :type => :double)
assert_equal ['bb'], tsv['aa']['FieldB']
```

### Reading Headerless CSV

If the CSV input has no header row, set `:headers => false`; TSV auto-generates artificial keys:

```ruby
text =<<-EOF
k1,a,b
k2,aa,bb
EOF

tsv = TSV.csv(text, :headers => false)
assert_equal %w(k2 aa bb), tsv['row-1']
```

Keys become `"row-0"`, `"row-1"`, ...; each row's data is accessible as a plain array.

## Edge Case Handling and Advanced Options

- **Headerless + Unspecified Key:** Without headers or explicit key, rows are referenced as `"row-0"`, `"row-1"`, etc.
- **Multiple Mappings (`key_field`/`fields`):** When using these together, TSV performs an internal `:double` mapping with `:merge`, then reorders per specification, and finally converts to the requested output type (`:single`/`:list`/`:flat` if specified).
- **Type Conversion:** The `:cast` option lets you apply any method (e.g., `:to_f`, `:to_sym`) to all field values as they are parsed.
- **Type Normalization:** If you specify a type that differs from the temporary structure used for reordering, the result is converted to its appropriate form, ensuring expected behavior for both list-like and mapping types.

## Options Reference

| Option      | Purpose                                                                                                  | Default   |
|-------------|----------------------------------------------------------------------------------------------------------|-----------|
| `:headers`  | Boolean: first row is headers (`true`) or not (`false`)                                                  | `true`    |
| `:type`     | TSV value structure: `:list`, `:double`, `:flat`, `:single`                                              | `:list`   |
| `:key_field`| Which CSV field(s) to designate as the key for the TSV structure                                         | First col |
| `:fields`   | Which CSV fields to include as TSV values                                                                | All but key|
| `:cast`     | Method symbol (e.g., `:to_f`) to apply to every value                                                    |           |
| `:merge`    | Controls merging of duplicate keys/fields into arrays (automatically enabled with field/key remapping)   |           |

## Test-Derived Behaviors

- Headerless tables are key-accessed by `"row-0"`, `"row-1"`, etc.  
  `assert_equal %w(k2 aa bb), tsv['row-1']`
- Key/field mapping can be combined with specific value type, and automatic value conversion occurs as shown in:
  `assert_equal ['bb'], tsv['aa']['FieldB']`
- Output object always responds to field and key-based lookups in TSV idioms even if source was CSV.

## Integration and Extension

- Full field reordering, type adjustment, and casting capabilities inherit those of the `TSV` framework.
- Use the same annotation and pipeline conventions as standard TSV files.
- Accepts any format or input type supported by Ruby's CSV, plus Open and Path extensions.

See the main [`tsv`](../tsv.rb) documentation for further downstream usage and cross-integration.