# Association

Association provides a compact toolkit to open, normalize, and index pairwise relationships from TSV-like sources. With it you can:

- Parse declarative source/target field specifications (including format remapping).
- Open an “association database” (TSV) that standardizes keys/fields and optional identifier translation via Entity/TSV indices.
- Build a fast BDB-backed index over pair “edges” using “source~target” keys, optionally undirected.
- Work with association “items” (pairs) as Entities with useful properties and conversions.
- Produce incidence/adjacency matrices and perform filtering/subsetting over pairs.

It integrates with:
- TSV (parsing, reordering, indices)
- Entity (format registry and identifier translation)
- Persist (caching/DB backends)

Sections:
- Field specification syntax and normalization
- Opening association databases
- Building and using association indices
- AssociationItem: entity properties over pairs
- Matrix utilities
- Examples

---

## Field specification syntax and normalization

Association accepts flexible “field specs” to declare which columns are source and target, optionally including header aliases and format conversions.

Syntax patterns (strings):

- "FieldName"
  - Use the column named FieldName.
- "FieldName=~Header"
  - Use field FieldName but present it as Header in outputs.
- "=~Header"
  - No explicit field (infer from header or Entity format), but present as Header.
- "FieldName=>TargetFormat"
  - Use FieldName and translate identifiers to TargetFormat (via TSV.translation_index / Entity identifiers).
- "FieldName=~Header=>TargetFormat"
  - Full form; pick field, rename header, and convert identifiers.

Parsing and normalization helpers:
- Association.parse_field_specification(spec) -> [field, header, final_format]
- Association.normalize_specs(spec, all_fields=nil) -> normalized [field, header, format]
  - If a field is not directly present but is a recognized Entity format, it tries to find a matching column within all_fields by that Entity.

Extract source/target specs:
- specs = Association.extract_specs(all_fields, options)
  - options keys: :source, :target, :source_format, :target_format, :format (hash of entity_type -> default_target_format)
  - Returns a Hash with:
    - :source => [field, header, final_format]
    - :target => [field, header, final_format]
  - Infers default source/target when not provided:
    - If both nil → source := key_field; target := first data field
    - If source nil but target is key → source := first data field; and vice versa

Resolve headers and positions:
- Association.headers(all_fields, info_fields=nil, options)
  - all_fields: [key_field, field1, ...]
  - info_fields: extra value columns to keep besides target (defaults to “all” except source and target).
  - Returns:
    - [source_pos, field_pos, source_header, field_headers, source_format, target_format]
  - Handles :format hash defaults per entity type, and honors explicit source/target formats.

---

## Opening association databases

Association.open coerces a TSV (file/Path/TSV) into a normalized association database with optional identifier translation.

```ruby
db = Association.open(
  file_or_tsv,
  source: "Wife (ID)=>Alias",
  target: "Husband (ID)=>Name",
  namespace: "person",   # optional; replaces NAMESPACE placeholders in paths
  type: :list            # optional TSV type; inferred when not set
)
```

Behavior:
- Reads header and infers positions via headers(...).
- If target/source formats are specified:
  - Builds translation indices from:
    - TSV.identifier_files(file), Entity.identifier_files(format), and options[:identifiers].
  - Rewrites keys/values to requested formats (e.g., “(ID)=>Name”).
- Produces a TSV with:
  - key_field: resolved source field name (with “(format)” suffix if translated).
  - fields: [resolved target field (with “(format)” if translated), plus remaining info_fields].
  - type: inherited/passed (:double, :list, :flat, :single).

Namespace placeholder:
- When opening from a path string containing “NAMESPACE”, passing namespace: will substitute it:
  - Example: ".../NAMESPACE/identifiers.tsv" -> ".../person/identifiers.tsv"

Persisted variant:
- Association.database(file, ...) wraps Association.open with Persist.tsv and a “BDB” engine:
  - Returns a persistence-backed TSV (keys/fields/type saved with TSVAdapter).
  - Options: any Association.open options plus :persist / persist_* (via IndiferentHash).

Examples:
- Simple open:
  ```ruby
  db = Association.database(datadir.person.marriages,
                            source: "Wife", target: "Husband", persist: true)
  db["Clei"]["Husband"]  # => "Miguel"
  db["Clei"]["Date"]     # => "2021"
  ```

- Partial field + format:
  ```ruby
  db = Association.database(datadir.person.marriages,
                            source: "Wife=>Alias", target: "Husband=>Name")
  ```

- Flat TSV:
  ```ruby
  flat = datadir.person.parents.tsv(type: :flat, fields: ["Parent"])
  db = Association.database(flat)
  db["Miki"]  # => %w(Juan Mariluz)
  ```

---

## Building and using association indices

Association.index materializes a BDB index over pairwise relations with keys of the form “source~target”. The index entries store the “info fields” (everything but the two endpoints) as a :list TSV.

```ruby
idx = Association.index(file_or_tsv,
                        source: "=>Name",
                        target: "Parent=>Name",
                        undirected: false,  # true duplicates (source~target) and (target~source)
                        persist: true)
```

- Under the hood:
  - Opens/normalizes the database with Association.open (or uses provided DB).
  - Builds keys “[source]~[target]” and writes values (info fields) as a list.
  - If undirected true (or same source/target column), writes both “[s]~[t]” and “[t]~[s]”.

- Return value:
  - A BDB TSV extended with Association::Index, annotated with:
    - source_field, target_field, undirected
  - The index sets key_field to “SourceField~TargetField[~undirected]”.

- Methods on Association::Index:
  - parse_key_field → sets source_field/target_field/undirected from key_field.
  - match(entity) → returns all “source~target” keys whose source starts with entity (prefix-based).
  - subset(source_list, target_spec)
    - source_list: list of source entities or :all.
    - target_spec: :all or list to filter by target side.
    - Returns matching keys, handling undirected symmetry.
  - reverse → returns a reversed index (keys swapped to “target~source”) persisted in a side file (.reverse).
  - filter(value_field=nil, target_value=nil, &block)
    - Without block: filter keys whose value_field is present (or equals target_value).
    - With block: custom predicate over values (or key+values if value_field nil).
  - to_matrix(value_field=nil) { |values| ... }
    - Produces an incidence matrix TSV (rows: sources, columns: targets):
      - If value_field provided, uses that column (or block mapping).
      - Else boolean incidence.

Note:
- reverse persists its own DB with swapped key_field; it carries over annotations, unnamed flag, and undirected.

Example:
```ruby
idx = Association.index(datadir.person.brothers, undirected: true)
idx.match("Clei")           # => ["Clei~Guille"]
idx.reverse.match("Clei")   # => ["Clei~Guille"] (same when undirected)
idx.filter("Type", "mother")
idx.subset(["Miki","Guille"], :all) # some “source~target” keys
```

---

## AssociationItem: entity properties over pairs

AssociationItem is an Entity module that represents “pairs” as annotated strings “source~target”. You typically obtain such lists from index.keys, and then call properties on the annotated list.

Annotate:
- Association.index(file).keys returns raw strings; annotate them with AssociationItem.setup if needed, or use Index helpers that return annotated where applicable.

Properties (selected):
- name (single): "source~target" (returns friendly names using entity .name where available).
- full_name: database-prefixed “db:source~target” when database set.
- invert: swap endpoints (works on single or array); toggles reverse flag.
- namespace: forwarded from knowledge_base (if present).
- part (array2single): returns [source, "~", target] tuples for each pair.
- target / source (array2single): returns just target or source identifiers.
- target_type / source_type (both): resolve entity type names via knowledge_base target/source (requires a KnowledgeBase integration providing #source/#target/#undirected/#get_index/#index_fields).
- target_entity / source_entity: wrap target/source into Entity-typed values according to knowledge_base types.
- index(database=nil): resolve underlying index (delegates to knowledge_base.get_index).
- value (array2single): fetch info values for each pair from the index; returns NamedArrays.
- info_fields / info: helper for value lookups; info builds a Hash for each pair.
- tsv (array): emit a TSV for the pair list with columns: source_type, target_type, info_fields.
- filter(*args, &block): filter this pair list using the generated tsv.select.

Utilities:
- AssociationItem.incidence(pairs, key_field="Source") { |pair| optional_value }
  - Returns TSV (list) with rows as sources and columns as targets; cells are blocks’ value or booleans.
- AssociationItem.adjacency(pairs, key_field="Source") { |pair| value }
  - Returns TSV (double) mapping source -> [Target, values].

Convenience:
- TSV.incidence(tsv, **kwargs) delegates to Association.index(...).keys -> AssociationItem.incidence

---

## Matrix utilities

Given an index:
- idx.to_matrix(value_field=nil) { |values| ... } → TSV list
  - value_field omitted and no block → boolean incidence.
  - With value_field → use that column (vector) as the cell value.
  - With block → compute cell values programmatically.

Standalone:
- AssociationItem.incidence/pairs as above.
- AssociationItem.adjacency for adjacency list.

---

## Examples

Parse specs:
```ruby
Association.parse_field_specification("=~Associated Gene Name=>Ensembl Gene ID")
# => [nil, "Associated Gene Name", "Ensembl Gene ID"]

Association.normalize_specs("TG=~Associated Gene Name=>Ensembl Gene ID", %w(SG TG Effect))
# => ["TG", "Associated Gene Name", "Ensembl Gene ID"]

Association.extract_specs(%w(SG TG Effect), source: "SG", target: "TG")
# => { source: ["SG", nil, nil], target: ["TG", nil, nil] }
```

Open database (translate to human-readable names):
```ruby
db = Association.database(datadir.person.marriages,
                          source: "Wife (ID)=>Alias",
                          target: "Husband (ID)=>Name")
db["Clei"]["Husband"]  # => "Miguel"
db["Clei"]["Date"]     # => "2021"
```

Index and match:
```ruby
idx = Association.index(datadir.person.brothers, undirected: true)
idx.match("Clei")  # => ["Clei~Guille"]
idx.subset(["Clei"], :all) # => ["Clei~Guille"]
idx.reverse.subset(["Guille"], :all) # => ["Guille~Clei"]
```

Filter:
```ruby
idx = Association.index(datadir.person.parents)
idx.filter('Type of parent', 'mother') # keys whose info field contains 'mother'
```

Incidence matrix:
```ruby
pairs = Association.index(datadir.person.brothers, undirected: true).keys
inc = AssociationItem.incidence(pairs)
inc["Clei"]["Guille"] # => true
```

List serializer handling:
```ruby
tsv = TSV.open <<~EOF
#: :sep=,#:type=:list
#lowcase,upcase,double,triple
a,A,aa,aaa
b,B,bb,bbb
EOF
i = Association.index(tsv)
i["a~A"] # => ['aa', 'aaa']
```

---

## Notes and edge cases

- undirected default: if source_field == target_field, undirected is assumed true; else false unless set.
- When specifying formats, ensure identifier TSVs are reachable. You can pass :identifiers (TSV/Path) or rely on TSV.identifier_files(file) and Entity.identifier_files(format).
- Association.index returns a BDB-backed TSV; reverse indexing persists to a side .reverse database next to the main DB.
- Paths containing [NAMESPACE] or NAMESPACE are substituted with options[:namespace].