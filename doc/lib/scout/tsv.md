# TSV Module Comprehensive Documentation

The `TSV` Ruby module is a robust, high-performance infrastructure for handling tab-separated value (TSV) tabular data, enabling a wide range of scientific, data engineering, and bioinformatics applications. Its unified interface supports rich file parsing, annotation and metadata, flexible transformation, persistent storage, stream and parallel collection processing, field and key reorganization, and seamless integration with related tabular and identifier resources. The following manual compiles all key TSV submodules and features into one complete reference, richly illustrated with code examples and derived behaviors.

---

## Core Module Overview and Annotation System

### Features

- **TSV Setup & Annotation:** Automatically or programmatically associate tabular data structures (hashes, arrays) with rich metadata: key fields, field names, table type (`:single`, `:double`, `:list`, `:flat`), value casting, filename, identifiers, serializer information, and more.
- **Flexible Parsing:** Supports input from files, IO streams, inline strings, and remote URLs, accepting both headered and headerless formats.
- **Persistence:** Leverages TokyoCabinet for disk-backed tables, automatic persistence, and seamless in-memory/ondisk transitions.
- **Field Specification:** Allows fields to be specified or inferred by name, string, or numeric index, and supports dynamic reordering and lookups.
- **Advanced Query Facilities:** Filter, grep, and select rows or fields with regex/string queries or custom logic.
- **Entity and Identifier Integration:** Lookup and remap data using identifier files, enabling powerful join and translation workflows.
- **Annotation Propagation:** All tabular objects and arrays can carry their annotation hash, preserved across nearly every manipulation.

### Basic Usage Examples

#### Opening TSV Files

```ruby
content =<<-'EOF'
#: :sep=/\s+/#:type=:double#:merge=:concat
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    a    a    id3
EOF

tsv = TmpFile.with_file(content) { |filename| TSV.open(filename) }
assert_include tsv.keys, 'row4'
assert_include tsv.keys, 'row1'
```

#### Using Persistence

```ruby
tsv = TmpFile.with_file(content) do |filename|
  TSV.open(filename, :persist => true)
  Persist::CONNECTIONS.clear
  TSV.open(filename, :persist => true)
end
assert_equal "Id", tsv.key_field
assert_equal TokyoCabinet::HDB, tsv.persistence_class
```

#### Headerless/Custom Field Handling

```ruby
tsv = TSV.open(filename, :sep => /\s+/, :fields => [1])
assert_equal ["a", "aa", "aaa"], tsv["row1"][0]
assert_equal :double, tsv.type
```

#### String-Based Annotation Setup

```ruby
tsv = TSV.str_setup("ID~ValueA,ValueB#:type=:flat", {})
assert_equal "ID", tsv.key_field
```

#### Field and Key Customization

```ruby
tsv = TSV.open(filename, :sep => /\s+/, field: "ValueB")
assert_equal "b", tsv["row1"]
```

#### Grep and Row Filtering

```ruby
tsv = TSV.open(filename, :key_field => "Value", :grep => "#\\|2")
assert_includes tsv, "2"
refute_includes tsv, "3"
```

#### Hash Conversion

```ruby
hash = tsv.to_hash
refute TSV === hash
```

### Identifier File Integration

```ruby
tsv = datadir_test.person.marriages.tsv
assert tsv.identifier_files.any?
```

---

## Attachment and Rich Annotation

The `TSV` attachment and annotation system supports attaching metadata, custom casting, and identifier links, enabling precise introspection and advanced field/key manipulation.

- All relevant TSV instance attributes (`key_field`, `fields`, `type`, `cast`, `filename`, `namespace`, `unnamed`, `identifiers`, `serializer`, `entity_options`) are settable and can be queried for every TSV or record.
- Headers and string-based options can drive the configuration and subsequent access patterns while guaranteeing proper field and type annotation across operations.

---

## Identifier Change and Translation (`change_id`, `change_key`, `translate`)

Comprehensive mechanisms allow changing the key field and translating between fields in the same or related TSVs, potentially traversing a mapping chain.

- **`change_key`:** Transforms the table to use a new key field, with options for merging, streaming, one-to-one mapping, and identifier file fallback.
- **`change_id`:** Changes identifiers between columns or via linked files, for schema normalization.
- **`translate`:** Maps values across potentially multiple TSV-linked files, chaining mappings as necessary.

Examples:
```ruby
res = tsv.change_key "ValueA", keep: true
assert_equal ["row1"], res["A1"]["ID"]
```
```ruby
marriages = marriages.translate "Husband (ID)", "Husband (Name)"
assert_equal "Cleia", marriages["Miguel"]["Wife"]
```
- Translation chaining, index persistence, and robust fallback/error reporting are provided for real-world, multi-source identifier flows.

---

## CSV Integration

The `TSV.csv` helper reads CSV data (as string, path, IO, or remote source) and exposes it in TSV structure:

```ruby
text =<<-EOF
Key,FieldA,FieldB
k1,a,b
k2,aa,bb
EOF

tsv = TSV.csv(text)
assert_equal 'bb', tsv['k2']['FieldB']

tsv = TSV.csv(text, :key_field => 'FieldA', :type => :list)
assert_equal 'bb', tsv['aa']['FieldB']
```

Options include header auto-detection, key and field selection, flexible output types, merging, and value casting. Headerless CSVs are also supported.

---

## Dumper (Serialization and Streaming Output)

The `TSV::Dumper` class serializes TSV data to strings, IO, or files, handling headers, type-specific value formatting, and thread-safety, with options for compaction and streaming:

```ruby
dumper = TSV::Dumper.new :key_field => "Key", :fields => %w(Field1 Field2), :type => :double
dumper.init
dumper.add "a", [["1", "11"], ["2", "22"]]
```
```ruby
assert_equal txt, tsv.to_s
```
Handles exceptions and thread-cancellation gracefully for reliable background writing.

---

## Indexing

TSV supports rapid indexing for single field mapping, range-based interval queries, and point-based lookups, enabling efficient subsetting and retrieval:

```ruby
index = TSV.index(filename, :target => "ValueB")
assert_equal "OtherID", index.fields.first

# Range index example:
f = tsv.range_index("Start", "End", :persist => true)
assert_equal [], f[0].sort
```

- Both functional and object-oriented APIs provided.
- Persistence and progress logging supported for long-running computations.

---

## Open, Streams, and Traversal

`TSV.open` and `TSV.traverse` allow flexible processing and collection of data from files, TSVs, arrays, streams, IO, and more—supporting serial or parallel processing.

```ruby
r = TSV.traverse lines, :into => [], :cpus => 2 do |l|
  l + "-" + Process.pid.to_s
end
```
- Output directed to array, set, hash, dumper, stream, or file.
- Handles file streaming, collapse by key, indexed traversal, and supports error propagation across parallel tasks.

---

## Parser: Core File and Stream Parsing

All TSV parsing is handled by the `TSV::Parser`, which extracts headers, fields, values, and annotates structure accordingly. Flexible options exist for key field placement, value type, merging, casting, header lines, custom separators, and more.

```ruby
key, values = TSV.parse_line(line)
tsv = TSV.parse(content, fields: %w(ValueB))
```
- Grep-based filtering, per-row selection, and custom fixes are supported.
- Direct-to-database loading enables memory-efficient ingestion of large datasets.

---

## Path Integration

The `Path` abstraction is deeply integrated, allowing you to treat any file as a `TSV` resource simply by calling `path.tsv`, with direct access to header parsing, persistence, field selection, and identifier file discovery.

```ruby
Path.setup(filename)
tsv = filename.tsv persist: true, merge: true, type: :list, sep: /\s+/
```
- Methods such as `tsv_options` and `index` are also available on Path objects.

---

## Streams

The TSV streaming API supports real-time reading, writing, and data transformation, including with file-attached or persistent tables. 

- Annotate, parse, and manipulate both lines and structured records in a streaming fashion.
- Filter rows during parsing, cast values, and convert in-flight between memory and persistent storage as needed.
- Attach identifier mapping for enrichment in real time.

---

## Transformer: Table Structure and Type Transformation

The `TSV::Transformer` class wraps tables or parsers and allows arbitrary "reshape" or value transformation. Easily switch types (`:flat`, `:double`, `:list`, `:single`), set key/field/metadata, and stream transformed rows into custom dumpers, hashes, or files.

```ruby
trans = TSV::Transformer.new parser, dumper
dumper = trans.traverse do |k, values|
  [k, values.flatten]
end
tsv = trans.tsv
```
- Methods for direct conversion: `to_list`, `to_single`, `to_flat`, `to_double`
- Supports addition and in-place edits.

---

## Traverse

`TSV#traverse` is the key for iterating and transforming tables flexibly:

- Redefine the key or fields on the fly, e.g., traverse "OtherID" as key, selecting "Id" and "ValueB" as fields.
- Return flat, list, single, or double structures, annotated values, and preserve metadata.
- Integrate select/invert/select options, one-to-one row expansion, and on-the-fly annotation for entity-aware workflows.
- Returns `[key_field, fields]` describing the resulting table format.

---

## Utility Methods

TSV utilities cover row filtering, selection, reordering, sorting, melting (reshaping wide-to-long), field identification, summarization, fingerprinting, and summary reporting.

- Access fields and field names/positions by name or index.
- Obtain quick table summaries (`summary`), and merge or zip other tables.
- Annotated access and iteration are preserved, or can be temporarily suppressed for speed (`with_unnamed`).
- File-level operations to count matching values per field efficiently.

---

## Edge Case Handling and Robustness

All modules and methods are validated across a comprehensive test suite, covering:

- Both headered and headerless TSVs
- Flat/double/single/list value structures
- Nil, empty, sparse, or multi-valued data
- File, IO, array, and Hash input/output sources
- Identifier mapping and translation chains
- Persistence and in-situ updating
- Exception handling and parallel/concurrent processing

---

## References and Further Information

- [Scout annotation framework documentation](https://github.com/mikisvaz/scout/)
- All source and test files (`lib/scout/tsv/`, `test/scout/tsv/`, etc) for in-depth behaviors, usage, and advanced API.

---

This documentation combines descriptions and direct examples from the project test suite and source. It is designed to provide everything needed to leverage the power and flexibility of TSV in a wide variety of tabular data workflows and scientific computing pipelines.