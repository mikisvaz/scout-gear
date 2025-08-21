# TSV

TSV is a flexible table abstraction for delimited data with rich metadata, streaming, persistence, and transformation utilities. It provides:

- A typed table model with explicit key_field and fields, supporting four shapes: :double, :list, :flat, :single.
- Robust parsing from files, streams or strings (with header options), plus CSV support.
- Streaming writers (Dumper) and transformation pipelines (Transformer).
- Parallel traversal (cpus) with WorkQueue and thread-safe streaming via ConcurrentStream.
- Index builders (exact, point and range indexes) for fast lookups.
- Identifier translation and key/field re-mapping (change_key/change_id/translate).
- Table joins/attachments (attach) with fuzzy field matching, identifier indices and completion.
- Streaming table operations (paste/concat/collapse).
- Column operations: reorder/slice/column/transpose; melt, add_field, process, remove_duplicates, sorting, paging.
- Filters for on-disk or in-memory row selection that transparently affect iteration.
- Integration with Annotation/Entity (field-aware NamedArray on rows, entity-typed values).
- Path helpers and persistence through ScoutCabinet/TokyoCabinet.

Sections:
- Data model and setup
- Parsing and opening
- Dumper (writing) and Transformer (pipelines)
- Traversal and parallelization
- Indexing and position/range indices
- Identifier translation and key/field changes
- Attaching tables
- Streaming utilities (paste/concat/collapse)
- CSV utilities
- Column and row utilities (process/add_field/melt/select/reorder/transpose/unzip)
- Filters
- Annotation integration (annotated objects <-> TSV)
- Path integration and identifier files
- Persistence notes
- CLI: scout tsv
- Examples

---

## Data model and setup

A TSV is a Hash-like object extended with Annotation:

- key_field — name of the key column.
- fields — array of field names (data columns).
- type — shape of values:
  - :double → Array of Arrays per field; row is fields.length arrays.
  - :list → single array (one value per field).
  - :flat → flattened list (space- or sep2-joined values).
  - :single → single scalar value per key.
- cast — optional value casting (:to_i, :to_f, Proc).
- filename, namespace, identifiers, serializer — metadata.

Construct or annotate:
- TSV.setup(hash, key_field:, fields:, type:, ...) — extend an existing hash.
- TSV.setup(array, ...) — converts to a hash-of-arrays with appropriate default.

Convenience:
- TSV.str_setup("ID~FieldA,FieldB#:type=:flat", obj) — parse an option string.
- TSV.str2options("ID~FieldA,FieldB#:type=:flat") — option parser.

Each row’s value is typically a NamedArray bound to fields (unless unnamed true).

---

## Parsing and opening

Open from a file/stream/string with automatic header parsing and options:

- TSV.open(file, options = {}) → TSV

Header format (optional):

- First line (preamble options): "#: key=value#key=value ..."
  - Common keys: :type, :sep, :cast, :merge, :namespace
- Second line (header): "#Key<sep>Field1<sep>Field2..."

Options (selected):
- sep (default "\t"), sep2 (default "|")
- type (:double default), merge (:concat supports multi-rows merge)
- key_field (name or :key)
- fields ([names] or :all)
- field: name — shortcut to request only one field (type defaults to :single)
- grep/invert_grep/fixed_grep — pre-filter raw input via Open.grep
- tsv_grep — grep by keys in a TSV-aware way
- head — limit rows
- cast — :to_i/:to_f/Proc
- fix — true or Proc (line fixups)
- persist: true — persistence-backed storage (default engine :HDB via TokyoCabinet)
  - persist_path, persist_prefix, persist_update, data: data cabinet
- unnamed — when true, row values are plain arrays (no NamedArray)
- entity_options — used when wrapping values as entities
- monitor/bar — log/progress control

Direct parser:
- TSV::Parser.new(io_or_path, sep:, header_hash:, type:) — exposes options, key_field, fields, first_line, preamble.
- TSV.parse(stream_or_parser, ...) — lower-level parse, can write into persistent data stores (data: ScoutCabinet).

Detect header/options without full parse:
- TSV.parse_header(io_or_path) → NamedArray[options, key_field, fields, first_line, preamble, all_fields, namespace]
- TSV.parse_options(file) → options hash

CSV:
- TSV.csv(obj, headers: true, type: :list, key_field:, fields:, cast:, merge:) — convenience CSV loader.

Path helpers:
- Path#tsv(args) — produce/find and open with TSV.open
- Path#tsv_options(options) — return parsed header options
- Path#index(...) — build an index on a TSV path

---

## Dumper and Transformer

Dumper writes TSV streams with preamble and header:

- TSV::Dumper.new(key_field:, fields:, type:, sep: "\t", compact:, filename:, namespace:)
- dumper.init(preamble: true|String)
- dumper.add(key, value) — value shape depends on dumper.type; supports :double (lists-of-lists) with "|" join.
- dumper.stream — readable IO (ConcurrentStream-enabled)
- dumper.tsv — parse its own stream back to a TSV
- TSV#dumper_stream(into:, preamble:, keys:, unmerge:, stream:) — generate a stream from a TSV (optionally unmerge :double rows into multiple lines).

Transformer is a pipeline wrapper that reads from a TSV/Parser and writes via a Dumper:

- TSV::Transformer.new(source, dumper=nil, unnamed: nil, namespace: nil)
- transformer.key_field=, fields=, type=, sep=
- transformer.traverse { |key, values| [new_key, new_values] } — each block call should return a [key, value] tuple to add.
- transformer.each { |key, values| ... } — also supports appending via transformer[key] = value.
- transformer.tsv — finalize and load as TSV.

---

## Traversal and parallelization

Uniform traversal API (works for TSV, Hash, Array, IO, Parser and Step):

- TSV.traverse(obj, into: nil, cpus: nil, bar: nil, unnamed: true, callback: nil, type:, key_field:, fields:, cast:, select:, one2one:, head:, sep:, ...) { ... }
  - into: :stream | IO | TSV::Dumper | Array | Set | Path | nil
  - cpus: n — parallelize with WorkQueue; your block runs in child processes on serialized arguments.
  - bar: true or ProgressBar options — handy progress indication.
  - Selection: select can be regex/symbol/string/Hash; invert via select: {invert: true}.

Examples:
- TSV.traverse(tsv, into: [], cpus: 2) { |k, v| "#{v[0][0]}-#{Process.pid}" }
- TSV.traverse(lines, into: :stream) { |line| line.upcase }

Header-aware helpers:
- TSV.process_stream(stream) { |sin, first_non_header_line| ... } — pass-through header lines, handle the payload.
- TSV.collapse_stream(stream) — preserve headers, collapse body via Open.collapse_stream.
- TSV#collapse_stream — convenience calling TSV.collapse_stream on self.

---

## Indexing

Build mapping indices (value→key or with fields):

- TSV.index(tsv_or_path, target:, fields: :all or [names], order: true, persist: true|false, bar:, select:, data: options)
  - Returns a persistence-backed single-type TSV (adapter) mapping any value (in fields) to the first observed target key.
  - With order: true (default), builds a “first seen” mapping across merge.
  - With fields specified, restricts to those fields; fields == :all includes the key itself.

Position/range indices (FixWidthTable-backed):
- TSV.pos_index(tsv, pos_field, key_field: :key, persist:) — point queries (pos or pos range) → list of keys.
- TSV.range_index(tsv, start_field, end_field, key_field: :key, persist:) — range queries → keys overlapping a pos or range.

---

## Identifier translation and key/field changes

Translation across one or more identifier files:

- TSV.translation_index(files, source, target, persist: true) → index mapping source → target
  - files may be TSV instances, paths or arrays of both.
  - source can be nil (auto-resolve via path across files).
- TSV.translate(tsv, field, format, identifiers: nil, one2one:, merge:, stream:, keep:, persist_index:) → translated TSV
  - If field is key_field, changes the key; otherwise changes a column.

Change key by column (with identifiers fallback):
- TSV.change_key(source, new_key_field, identifiers: nil, one2one: false, merge: true, stream: false, keep: false, persist_identifiers: nil)

Change an ID column to a different format (attach identifiers and slice):
- TSV.change_id(source, source_id, new_id, identifiers: nil, one2one: false, insitu: false)

---

## Attaching tables

Join “other” fields onto “source” keyed by matching columns:

- TSV.attach(source, other, target: nil|:stream|tsv, fields: nil, index: nil, identifiers: nil, match_key: nil, other_key: nil, one2one: true, complete: false, insitu: (TSV? default true), persist_input: false, bar: nil)

Key logic:
- match_keys picks (match_key, other_key) by fuzzy name matching (NamedArray.field_match), falling back to key fields if needed.
- If “other” is not a TSV instance, it is opened with key_field=other_key.
- If keys don’t align directly, build/accept an index via TSV.translation_index(identifiers).
- Shapes are reconciled (single/list/double/flat) to fit source.type; missing values filled appropriately.

Flags:
- complete: true — add keys present in “other” but missing in “source” (only when match_key == :key).
- insitu: true — modify source in place (default for TSV); false — produce new object or write into target.

Examples:
- source.attach(other, complete: true)
- TSV.attach(file1, file2, target: :stream).tsv

---

## Streaming utilities

- TSV.paste_streams(streams, type: :double/:list/:flat, sort: true|false, sort_cmd_args:, sort_memory:, sep:, preamble:, header:, same_fields:, fix_flat:, all_match:, one2one:, field_prefix: [])
  - Aligns multiple TSV streams by key (optionally pre-sorted), merges their columns and emits a single stream with unioned fields.
- TSV.concat_streams(streams)
  - Concatenate multiple TSV streams preserving the first header and merging rows by key when read with merge: true.

---

## CSV utilities

- TSV.csv(obj, headers: true, type: :list, key_field:, fields:)
  - Load CSV-like content from String/IO/Path.
  - If key_field or fields are provided, returns a properly shaped TSV (reorders or converts type accordingly).

---

## Column and row utilities

Process and add new columns:
- TSV#process(field) { |field_values| ... } or { |field_values, key| ... } or { |field_values, key, row_values| ... } → self
- TSV#add_field(name = nil) { |key, row_values| new_values } → append a column.

De-duplicate:
- TSV#remove_duplicates(pivot = 0) → new TSV removing duplicate zipped rows (keeps unique element-wise tuples).

Melt columns:
- TSV#melt_columns(value_field, column_field) → long-form table with fields [key_field, value_field, column_field]

Selecting rows:
- TSV.select(key, values, criterion, fields:, field:, invert:, type:, sep:) → boolean (low-level)
- TSV#select(method=nil, invert=false) { |k, v| ... } → new TSV:
  - method can be: Array (membership), Regexp, String/Symbol, Hash (field => criterion), Numeric, Proc
  - In Hash form, :key targets keys; "name:..." supports entity name matching.
  - In String form ">=5" etc. for numeric thresholds.

Subsets and chunking:
- TSV#subset(keys)
- TSV#chunked_values_at(keys, max = 5000) → batched lookup lists (ordered).

Reorder and slicing:
- TSV#reorder(key_field=nil, fields=nil, merge: true, one2one: true, data: nil, unnamed: true, type:) → new TSV with new key and/or field selection.
- TSV#slice(fields) → shortcut to reorder by same key.
- TSV#column(field, cast:) → new single/flat column TSV.

Transpositions:
- TSV#transpose(key_field="Unknown ID") → transpose by rows/columns, shape-preserving:
  - list/double variants provide transpose_list/transpose_double.
- TSV#head(max=10) → first n rows.

Sorting and paging:
- TSV#sort_by(field=:all, just_keys=false) { |(k, v)| ... } — returns sorted [key, value] pairs or just keys.
- TSV#sort(field=:all, just_keys=false) { |a, b| ... }
- TSV#page(pnum, psize, field=nil, just_keys=false, reverse=false) — returns page slice or keys.

Unzip/zip:
- TSV#unzip(field, target: nil|:stream|tsv, sep: ":", delete: true, type: :list, merge: false, one2one: true, bar: nil)
  - Split each row by a field’s values, emitting new keys key+sep+field_value.
  - delete: removes that column when forming new rows.
  - merge: combine replicates by new key (deduplicate values).
- TSV#unzip_replicates — expand :double replicates into separate pseudo-rows (key(i)).
- TSV#zip(merge=false, field="New Field", sep: ":") — reverse after unzip (merge replicates optionally).

---

## Filters

Add persisted or in-memory filters affecting iteration transparently:

- tsv.filter(filter_dir=nil) — extend with Filtered; set filter_dir for persistent filters.
- tsv.add_filter(match, value, persistence=nil) — filter rows
  - match: "field:FieldName" to match on a field; :key to match on keys.
  - value: String or Array; stored as Set when needed.
  - persistence: Hash or HDB path for persistent cache of ids.
- tsv.pop_filter — remove last filter (finalize pending updates).
- tsv.reset_filters — delete all saved filters.

When filters are present:
- filename and keys/values/each/collect are transparently scoped to filtered ids.
- size returns filtered size.

---

## Annotation integration

Serialize annotated objects to TSV:

- Annotation.tsv(objs, *fields)
  - objs can be a single annotated object, an array of annotated objects, or annotated arrays.
  - fields defaults to all annotations + :annotation_types (or :all to include :literal).
  - Produces a TSV with key_field nil or special keys ("List" or object ids).
- Annotation.load_tsv(tsv) — reconstruct annotated objects from TSV.

Persist annotated objects into a repo (Tokyo Cabinet):
- Persist.annotation_repo_persist(repo_or_path, name) { annotations }
  - Stores or retrieves annotations by a name subkey; supports nil/empty, single objects, arrays, and annotated double arrays.

---

## Path integration and identifier files

- A TSV loaded from a Path gets filename set to that Path (and Path metadata).
- If a sibling “identifiers” file is present, it is auto-loaded into tsv.identifiers.
- Path#identifier_file_path conveniently locates such files.

Utilities:
- TSV#identifier_files — discover identifier TSVs from:
  - tsv.identifiers (if set),
  - tsv.filename.dirname.identifiers, or options.

---

## Persistence notes

- TSV.open with persist: true returns a persistence-backed TSV (ScoutCabinet/TokyoCabinet HDB by default). You can reopen the cabinet and still see options (key_field/fields/type).
- TSV.parse can directly stream data into persistence when data.responds_to?(:load_stream) and conditions allow (same type, no transformations) — faster load.

---

## Command Line Interface (scout tsv)

The scout command discovers TSV-related scripts under scout_commands/tsv across installed packages using the Path subsystem. Usage pattern:

- Listing and discovery:
  - scout tsv
    - If you specify a category (directory) rather than a script, a list of available subcommands is shown.
- Running a specific TSV subcommand:
  - scout tsv <subcommand> [options] [args...]
    - The dispatcher resolves to scout_commands/tsv/<subcommand> and executes it.
    - Remaining ARGV is parsed using SOPT (SimpleOPT) as specified by the subcommand.
- Nested commands:
  - Subcommands may themselves be directories; e.g., scout tsv attach ... would run scout_commands/tsv/attach if present, or list subcommands under attach if attach is a directory.

Script availability depends on installed TSV utilities in your environment (frameworks and workflows can register their own under share/scout_commands/tsv). Typical operations shipped by packages include attaching files, translating identifiers, building indexes, pasting/concatenating streams, and other TSV manipulations. Use scout tsv to explore installed commands.

Note: If the selected path is a directory, a help-like listing is printed. The bin/scout resolver uses Path to locate scripts from all installed packages.

---

## Examples

Open and traverse:

```ruby
content = <<~EOF
#: :sep=" " #:type=:double
#Id  ValueA  ValueB
row1 a|aa    b|bb
row2 A       B
EOF

tsv = TSV.open(StringIO.new(content))
tsv.unnamed = false
tsv.each do |k, v|
  puts [k, v["ValueA"]].inspect
end
# => ["row1", ["a","aa"]]
```

Attach:

```ruby
a = TSV.open <<~A
#: :sep=" "
#Id ValueA
row1 a
row2 A
A

b = TSV.open <<~B
#: :sep=" "
#Id Other
row1 X
row3 Y
B

a.attach(b, complete: true)
a["row1"]["Other"] # => ["X"]
a["row3"]["Other"] # => ["Y"] (added by complete)
```

Change key and translate:

```ruby
# tsv with identifiers mapping ValueA -> X
tsv = TSV.open(tf1, identifiers: ti)
tsv2 = TSV.change_key(tsv, "X")
tsv2.include?("x") # => true
```

Build an index:

```ruby
index = TSV.index(tsv, target: "ValueB")
index["a"] # => "b"
```

Paste streams:

```ruby
s1 = StringIO.new "#Row A\nr1 1\nr2 2\n".gsub(" ", "\t")
s2 = StringIO.new "#Row B\nr1 10\nr2 20\n".gsub(" ", "\t")
out = TSV.paste_streams([s1, s2], sort: true, type: :list)
TSV.open(out)["r2"] # => ["2","20"]
```

Unzip/zip:

```ruby
unzipped = tsv.unzip("ValueA", delete: true)
unzipped["row1:a"]["ValueB"] # => "b" (or ["b"] depending on type)
rezipped = unzipped.zip(true)  # merge back by base key
```

Filters:

```ruby
tsv.filter
tsv.add_filter "field:ValueA", ["A"]
tsv.keys # filtered keys only
tsv.pop_filter
```

CSV:

```ruby
tsv = TSV.csv("Key,FieldA\nk1,a\n", headers: true, type: :list)
tsv["k1"]["FieldA"] # => "a"
```

Annotation TSV:

```ruby
module A; extend Annotation; annotation :code; end
str = A.setup("s1", code: "C")
tsv = Annotation.tsv([str], :all)
list = Annotation.load_tsv(tsv) # => ["s1"] annotated back
```

---

TSV unifies table processing with streaming, persistence, and composable transforms, while interoperating with the rest of the Scout stack (Open, WorkQueue, Persist, Path, Annotation, and Entity). Use TSV.open/parse for ingestion, Dumper/Transformer for streaming pipelines, traverse for parallel computation, and the utility methods for reshaping and joining datasets. For CLI interaction, explore scout tsv subcommands provided by installed packages.