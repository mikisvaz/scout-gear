## Registry

The `registry` subsystem of the `KnowledgeBase` class provides the core methods and behaviors for registering, managing, and introspecting datasets ("databases" or "associations") and their metadata within a knowledge base. It is responsible for tracking files, options, identifier mappings, and other registry-level features that underpin all subsequent querying and graph-building activities.

### Registration Mechanism

Datasets are registered into the knowledge base using the `register` method, which stores them in the internal registry. Registrations may be done via file references or code blocks (for generated data), and may include associated options such as identifier mappings:

```ruby
brothers = datafile_test(:person).brothers
kb = KnowledgeBase.new dir
kb.register :brothers, brothers
assert_include kb.all_databases, :brothers
```

Registration with a custom identifiers mapping (for alias or code resolution) is also supported and is reflected during indexing:

```ruby
identifier =<<-EOF
#Alias,Initials
Clei,CC
Miki,MV
Guille,GC
Isa,IV
EOF
TmpFile.with_file(identifier) do |identifier_file|
  identifiers = TSV.open(identifier_file, sep: ",", type: :single)
  kb.register :brothers, brothers, identifiers: identifiers
  assert_include kb.get_index(:brothers, source: "=>Initials"), "CC~Guille"
end
```

In this test-derived example, registering with a CSV of aliases allows index lookups (e.g., using initials) to return correct results.

### Database Listing and File Management

- `present_databases` enumerates the physical `.database` files found in the KB directory.
- `all_databases` returns all datasets known to the registry, including both actively registered and present-on-disk associations.

You can check if a dataset is registered using `include?(name)` and retrieve files or options via `database_file(name)` and `registered_options(name)`.

### Fields, Pairing, and Relationship Metadata

- `fields(name)` lists available fields from the given database index.
- `pair(name)`, `source(name)`, and `target(name)` extract the entity types involved in a binary association.
- `undirected(name)` (aliased as `undirected?`) determines whether a relationship is undirected or directed (based on index metadata).

### Index and Database Retrieval

The registry supports robust and flexible retrieval of indexed data structures via `get_index(name, options = {})` and `get_database(name, options = {})`. These methods consult both the in-memory configuration and persistent files, applying override options and incorporating identifier or entity option overlays as specified. They handle options hashing, persistent caching, and will regenerate or re-bind indexes/databases as files (or blocks) change.

### Produce Shortcut

The `produce(name, *rest, &block)` method is a utility shortcut that registers data (from file or block) and immediately returns its index.

### Design and Extensibility

Underlying the registry system:
- All options and state are managed with indifferent-access hashes (symbol or string keys).
- Files can be provided as `Path` objects; their resolution (`find`) is handled internally.
- Block registration supports dynamic, programmatic, or on-the-fly association generation.
- Registry and index metadata is serializable for persistence and recovery.

### Robustness and Edge Cases

- If you try to retrieve a file or options for a name not present in the registry, sensible defaults or a `nil` value are returned.
- When opening files or blocks, index and database rebuilding logic (including option digests for unique keys/caching) ensures that updates or overrides do not result in stale data.

### Test-derived Usage Idioms

- Registration of datasets and presence checks are central for setup: `assert_include kb.all_databases, :brothers`.
- Custom identifier mappings can be bound at registration and tested via alternate index lookups: `assert_include kb.get_index(:brothers, source: "=>Initials"), "CC~Guille"`.

### Summary

The registry subsystem is foundational in the `KnowledgeBase` architecture, enabling stateful, extensible, and performant management of knowledge datasets. It handles flexible registration, persistent file tracking, option layering, and rich metadata introspection, all while providing the infrastructure necessary for robust entity and relationship modeling. Test-driven idioms demonstrate reliable registration and query interaction, setting a standard workflow for advanced knowledge engineering tasks.