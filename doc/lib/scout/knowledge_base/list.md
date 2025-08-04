## List Handling in `KnowledgeBase`

The `KnowledgeBase` class offers robust facilities for managing named lists—both simple arrays of values and complex, annotated entity lists—tightly integrated with the entity and association system. Through this functionality, users can persist, restore, enumerate, and delete lists of objects (such as entities or raw values) in a manner consistent with the overall knowledge base organization.

### Core Capabilities

- **`list_file`**: Determines the filesystem path of a list by name and, optionally, its associated entity type. This method includes strict checks to prevent directory traversal and supports intelligent extension handling (e.g., using ".tsv" for annotated lists).
- **`save_list`**: Persists a list to disk. If the list is an `AnnotatedArray` (typically representing a collection of entities with rich metadata), it is saved using TSV-based annotation. Otherwise, it is saved as a plain newline-delimited file.
- **`load_list`**: Loads a list by name (and optional entity type), restoring either an annotated list (with type metadata and enrichment) or a simple value array, based on file format inspection. This method gracefully handles attempted loads of non-existent lists and logs exceptions if they occur.
- **`lists`**: Returns a hash mapping list types (such as entity types or "simple") to arrays of list names available in the knowledge base storage directory, discovering lists dynamically from disk.
- **`delete_list`**: Removes a list from disk by name and, optionally, entity type. This operation uses file locking to avoid corruption and checks for existence and appropriate access.

### Usage Patterns and Test-Derived Scenarios

#### Entity-Linked Lists: Creation, Persistence, and Discovery

Storing and retrieving an entity-annotated list:

```ruby
kb = KnowledgeBase.new dir
kb.register :brothers, datafile_test(:person).brothers, undirected: true
kb.register :parents, datafile_test(:person).parents

list = kb.subset(:brothers, :all).target_entity
kb.save_list("bro_and_sis", list)
assert_equal list, kb.load_list("bro_and_sis")
```

The `save_list` method persists an `AnnotatedArray` of entities derived from the result of an association query. After saving, `load_list` returns the identical entity list, demonstrating lossless round-trip storage.

Lists are organized by entity type, enabling targeted discovery and management:

```ruby
assert_include kb.lists["Person"], "bro_and_sis"
kb.delete_list("bro_and_sis")
refute kb.lists["simple"]
```

Upon deletion, the list is removed and will not appear in further enumeration calls.

#### Simple Lists: Storing and Managing Value Arrays

You can also store and retrieve simple arrays (e.g., strings) as lists of type "simple":

```ruby
list = ["Miki", "Isa"]
kb.save_list("bro_and_sis", list)
assert_equal list, kb.load_list("bro_and_sis")

assert_include kb.lists["simple"], "bro_and_sis"
kb.delete_list("bro_and_sis")
refute kb.lists["simple"].any?
```

This ensures that users can persist arbitrary sets of values, not only entity objects, using a consistent idiom.

### Robustness, Edge Cases, and Safety

- If a list is requested but does not exist, a clear error is raised: `raise "List not found #{id}" if path.nil?`.
- On save failure (such as a disk error), any partially-written file is proactively removed to avoid leaving corrupted artifacts.
- The system uses exclusive file locks (`Open.lock`) for all write and delete operations to guarantee atomicity and protect against race conditions in parallel workloads.
- File system paths are strictly sanitized and resolved relative to the knowledge base directory, mitigating directory traversal or symlink attacks from malformed list IDs.

### Format Awareness and Interoperability

- Lists associated with entity types use `.tsv` files and are round-tripped as annotated, metadata-rich arrays (`AnnotatedArray`).
- Simple (non-entity) lists are stored as plain text and handled accordingly.
- The API transparently determines and handles the correct file format on load.
- Users can enumerate all lists by type, aiding in discoverability and UI integration.

### Summary

`KnowledgeBase` list handling empowers users to persist, recall, update, and organize both simple and semantically-rich sets of data in alignment with knowledge graph operations. It does so safely, format-consciously, and with minimal friction, smoothing workflows for extraction, annotation, sharing, and curation of custom entity subsets or groupings—demonstrated in detail by the accompanying tests and idioms.