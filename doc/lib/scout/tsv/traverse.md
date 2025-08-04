# TSV Traverse

The `traverse` method in the `TSV` module provides a highly flexible interface for iterating through and transforming tabular data in TSV structures, with powerful features for dynamically redefining keys, fields, value shape, filters, annotation awareness, and more. This method is central for advanced TSV workflows such as mapping, field reorganization, entity transformation, and data extraction, and is directly validated through a comprehensive set of test cases.

---

## Core Capabilities

- **Remap Keys and Fields**: Use any field (by name or position) as the row key, and select any fields or column order as the values.
- **Type Transformation**: Output data in any TSV type (`:double`, `:list`, `:single`, `:flat`) regardless of the original table's type.
- **Selection and Filtering**: Filter or subset rows using value criteria, field matches, or inverted selection logic.
- **One-to-One Expansion**: Control unrolling of multi-valued keys and fields, with strict or best-effort pairing.
- **Entity and Annotation Awareness**: Support for producing named arrays, annotated objects, or enriched entity values per output.
- **Return Structural Metadata**: Every traversal returns `[key_name, field_names]` describing the logical format of the resulting table.

The method is also aliased as `through`.

---

## Dynamic Key/Field Reorganization

The essential use of `traverse` is to refactor the underlying TSV data structure:

```ruby
# Remap the key to any column, select and reorder columns for the value.
tsv.traverse "OtherID", %w(Id ValueB), one2one: :strict do |k, v|
  res[k] = v
end
# After, res["Id33"] == [[nil], %w(BB)]
```

Column sets can be given as symbols, names, or indices. The same applies for the key. You can select all fields using `:all`:

```ruby
all_values = []
tsv.traverse "ValueA", :all do |k, v|
  all_values.concat(v)
end
```

Return structure is always `[key_field, fields]` for direct integration or further processing.

---

## Output Type Transformation

The output shape can be explicitly controlled regardless of source table type:

- `type: :double` – array-of-arrays per column
- `type: :list` – single list per key
- `type: :flat` – flat array per key
- `type: :single` – scalar value per key

Examples derived from tests:

```ruby
# From double to list:
tsv.traverse :key, %w(OtherID ValueB), type: :list do |k, v|
  res[k] = v
end
# res["row2"] == ["Id3", "B"]

# From list to double:
tsv.traverse :key, %w(OtherID ValueB), type: :double do |k, v|
  res[k] = v
end
# res["row2"] == [%w(Id3), %w(B)]
```

Single-type extraction:

```ruby
tsv.traverse "ValueA", %w(Id) do |k, v|
  res[k] = v
end
# res["a"] == "row1"
```

---

## One-to-One and Multi-Valued Expansion

The `one2one` option enables fine control over one-to-many key mapping:

```ruby
# Strict index-based expansion:
tsv.traverse "OtherID", %w(Id ValueB), one2one: :strict, type: :list do |k, v|
  res[k] = v
end
# Yields ["row2", "B"] for "Id3", [nil, "BB"] for "Id33"
```

Less strict expansion (`one2one: true`) will repeat first values as needed, facilitating many-to-many projections.

---

## Selection and Filtering

Filter records using exact matches, field queries, or inverted logic:

```ruby
# Filtering keys
tsv = TSV.open(filename, :persist => true, select: "B1")
assert_equal %w(row1), tsv.keys

# Filtering fields
all_values = []
tsv.traverse "ValueA", :all, select: {ValueA: "A"} do |k, v|
  all_values.concat(v)
end
```

Inverted queries are supported:

```ruby
tsv.traverse "ValueA", :all, select: {ValueA: "a", invert: true} do |k, v|
  all_values.concat(v)
end
```

---

## Annotation, NamedArray, and Entity Structures

Each value yielded can maintain rich annotation, including:

- `NamedArray` for named fields
- `AnnotatedArray` for entity preparations or metadata
- Values can be `Annotation::AnnotatedObject` for scalar fields

From test assertions:

```ruby
k, f = tsv.traverse "Id", ["ValueA"] do |k, v|
  data[k] = v
end
assert Annotation::AnnotatedObject === data["row1"]
```
Or, for flat/annotated array modes:

```ruby
assert AnnotatedArray === data["row1"]["ValueA"]
```

---

## Flat and Single Handling

The traverse logic adapts for `:flat` or `:single` tables:

```ruby
# Flat
tsv = TSV.open(filename, :sep => /\s+/, :type => :flat)
keys = []
tsv.through "vA" do |k, v|
  keys << k
end
# keys includes 'B'

# Single
tsv.traverse "ValueA", %w(Id) do |k, v|
  res[k] = v
end
# res["a"] == "row1"
```

---

## Comprehensive Example Behaviors

- Changing keys: traverse by any column, including original ID or value fields.
- Changing value fields: select, subset, or reorder columns at will.
- Changing data shape: force flat, list, double, or single, adapting the mapping.
- Filtering: select by field value, invert matches.
- Entity/annotation propagation: traverse with awareness of field/entity info.
- Strict one-to-one pairing: for mapping many-to-many relationships consistently.
- Metadata return: always receive logical `[key_name, field_names]`.

All major edge cases, type transitions, strictness options, and annotation/mapping combinations are thoroughly validated by the test coverage.

---

## Summary

`TSV#traverse` is the central method for advanced data projection, field/key remapping, annotation propagation, and flexible value extraction within TSV-based workflows. Its robustness is demonstrated in the test suite, and its flexible set of options supports nearly all real-world use cases for manipulating structured table data—ranging from entity annotation to advanced many-to-many field transformations.