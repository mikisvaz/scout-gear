## Change Identifier and Translation in TSV

The TSV module supports sophisticated mechanisms for changing key fields (identifiers) and translating between fields in one or more related tabular resources. This enables flexible schema normalization and powerful join and remapping workflows, essential in scientific and data integration pipelines.

### Changing Keys and Identifiers

#### `change_key`
`change_key` lets you reindex a TSV by a new key field. If the requested field does not exist in the data but does in an associated identifier table, `change_key` will auto-join through the identifier TSV(s):

```ruby
res = tsv.change_key "ValueA", keep: true
assert_equal ["row1"], res["A1"]["ID"]
assert_equal ["row1"], res["A11"]["ID"]
assert_equal ["row2"], res["A2"]["ID"]
```

File-based input is supported:
```ruby
res = TSV.change_key file1, "ValueA", one2one: true, keep: true
assert_equal ["row1"], res["A1"]["ID"]
assert_equal ["B1","B11"], res["A1"]["ValueB"]
```

With identifiers:
```ruby
res = tsv.change_key "ValueC", identifiers: identifiers, keep: true
assert_equal ["row1"], res["C1"]["ID"]
```

#### `change_id`
`change_id` enables translation between two non-key fields, with optional identifier TSV integration:
```ruby
res = tsv.change_id "ValueA", "ValueC", identifiers: identifiers
assert_equal ["C1","C11"], res["row1"]["ValueC"]
assert_equal ["C2","C22"], res["row2"]["ValueC"]
```

Edge-case handling ensures identifiers are auto-discovered if missing fields, and fallbacks raise clear errors.

### Translation Between Fields

#### `translate`

`translate` remaps a field to another identifier, optionally traversing multiple linked files:

```ruby
marriages = datadir_test.person.marriages.tsv
marriages = marriages.translate "Husband (ID)", "Husband (Name)"
marriages = marriages.translate "Wife (ID)", "Wife (Name)"
assert_equal "Cleia", marriages["Miguel"]["Wife"]
```

With multiple identifier files or indirect translation:
```ruby
tsv = TSV.open tf1, :identifiers => [ti1, ti2]
assert TSV.translate(tsv, tsv.key_field, "X").include? "x"
```

Streaming and persistent index creation are supported:
```ruby
index = TSV.translation_index([tf1, tf2, tf3], 'A', 'X')
assert_equal 'x', index['a']
assert_equal 'xx', index['aa']
```

#### Translation Path Discovery

When translating between fields through multiple files, TSV automatically determines the minimal path:

```ruby
# file_paths = {:file1 => %w(A B C), :file2 => %w(Y Z A), ... }
assert_equal [:file1], TSV.translation_path(file_paths, "C", "A")
assert_equal [:file1, :file2, :file3], TSV.translation_path(file_paths, "B", "X")
```

### Robustness and Edge Cases

- Supports both direct and chained translation across multiple tables.
- If the direct field is missing, tries to traverse all identifier resources.
- Raises informative errors if no mapping chain exists.
- Handles both headered and headerless files, and accepts objects, Hashes, files, and arrays.
- Streaming and on-disk (TokyoCabinet) variants are available for large or persistent data.

### Summary from Test Suite

- Demonstrates round-trip mapping and field translation with complex chained identifier relationships.
- Ensures data and annotation integrity for advanced pipelining and schema restructuring.
- All primary workflows (file, in-memory, streamed, multi-file) are covered in the comprehensive tests.

The TSV change_id and translation suite provides a foundation for real-world biological and scientific data integration, with automatable schema translations, identifier join capabilities, and robust API consistency throughout.