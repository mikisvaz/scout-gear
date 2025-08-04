## Attach: Combining and Enriching TSV Tables

The `TSV.attach` facility, along with the `TSV#attach` instance method, is a cornerstone feature for flexible enrichment, extension, and joining of tabular data sets (TSVs, CSVs, etc.), leveraging the rich annotation system described earlier. Attachment enables you to combine tables across matching or related fields, resolve key/identifier differences, propagate or join extra value columns, and control field composition in a metadata-aware and pipeline-friendly fashion.

### High-Level Behavior

- Attach merges another TSV (or compatible source) into a base table, matching keys or fields.
- Supports field selection, identifier mapping, join direction (by key or by value), full/completeness joins, and index-assisted mapping (for nontrivial identifier relationships).
- Automatically propagates and extends field and key annotations, maintaining semantic consistency.

### Key Features Illustrated

#### Basic Attach by Key

```ruby
content1 =<<-EOF
#: :sep=" "
#ID    ValueA    ValueB
row1    a|aa|aaa    b
row2    A    B
EOF

content2 =<<-EOF
#: :sep=" "
#ID    ValueB    OtherID
row1    b    Id1|Id2
row3    B    Id3
EOF

tsv = TSV.open(filename1)
other = TSV.open(filename2)
tsv.attach other, :complete => true
assert_equal %w(Id1 Id2), tsv["row1"]["OtherID"]
assert_equal %w(Id3), tsv["row3"]["OtherID"]
```

#### Attach on Alternate Keys or Value Fields

Attaching tables can align on fields other than the default key, supporting nontrivial joins:

```ruby
tsv.attach other, complete: true, match_key: "ValueB"
assert_equal %w(Id1 Id11), tsv["row1"]["OtherID"]
assert_equal %w(Id2.2 Id22.2), tsv["row2"]["OtherID"]
```

#### Attaching with Identifiers

Attachment leverages identifier files/fields when those provide necessary mappings:

```ruby
tsv1.identifiers = ids
tsv1 = tsv1.attach tsv2
assert_equal [["A"], ["C"]], tsv1["row2"]
```

#### Control Over Fields and Structure

Specify which new fields to attach, adapt or preserve source/other annotations, and handle joins between different value types (single/double/flat/list):

```ruby
tsv1.attach tsv2, fields: "OtherID"
assert_equal %w(ValueA ValueB OtherID), tsv1.fields
assert_equal %w(Id1 Id2), tsv1["row1"]["OtherID"]
```

#### Attaching When Keys Differ

Use custom indexes or mapping tables when there’s no direct key match:

```ruby
tsv1.attach tsv2, index: index
assert_equal %w(ValueA ValueB OtherID), tsv1.fields
assert_equal %w(Id1 Id2), tsv1["row1"]["OtherID"]
```

#### Complete Joins - Fill in for New Keys

With `:complete => true`, attach will append keys from the joined table that weren't in the source:

```ruby
res = tsv1.attach tsv2, :fields => ["ValueC"], complete: true
assert res["row2"].include?("C")
assert res["row3"].include?("CC")
```

#### Nil and Type Handling

Attach is robust to missing data, sparse columns, nils, and empty string values:

```ruby
assert_equal [nil, "B", nil], tsv1.attach(tsv2, :complete => true).attach(tsv3, :complete => true)["row1"]
```

#### Attach Streams and Transformers

Attachment works directly with streams or transformer wrappers:

```ruby
out = TSV.attach filename1, filename2, target: :stream, bar: false
tsv = out.tsv
assert_equal %w(Id1 Id2), tsv["row1"]["OtherID"]
```

#### Flexible Name Resolution

Attach can harmonize fields even when names differ or are indirect:

```ruby
out = TSV.attach filename1, filename2, target: :stream, bar: false
tsv = out.tsv
assert_equal %w(Id1 Id2), tsv["row1"]["OtherID"]
```

### Supporting Utility: `identifier_files`

Every TSV can expose its associated identifier files via `.identifier_files`, allowing for seamless and transparent access to mapping resources:

```ruby
tsv = datadir_test.person.marriages.tsv
assert tsv.identifier_files.any?
```

This supports workflows where field or key translation relies on external reference sets.

### Summary of Attach Capabilities

- **Annotation-aware**: Updated annotations (key_field, fields, identifiers) on the result.
- **Key flexibility**: Attach by default keys, field names, or via custom indexes.
- **Complete joins**: Optionally incorporate all new keys from the attached source.
- **Field resolution**: Attach a subset or all fields, avoid duplication, and maintain order.
- **Robust**: Handles nillable data, type mismatches, one-to-one/one-to-many expansions, and field overlap.
- **Streaming transformation**: Integration with streaming and transformer APIs for large-scale or real-time processing.

For advanced data integration pipelines, `TSV.attach` makes it easy to extend any table with extra columns, complex identifier translation, or reference-driven value aggregation, with full preservation and updating of structural metadata.

See also the [Annotation System](#core-module-overview-and-annotation-system) for details on how annotations power robust and self-describing table operations.