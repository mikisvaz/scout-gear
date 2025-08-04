# KnowledgeBase

The `KnowledgeBase` class is a robust Ruby framework for representing, organizing, persisting, and querying complex networks of entities and their relationships. It is designed to handle namespaced datasets ("knowledge bases"), manage flexible registries of associations, and enable rich querying, annotation, traversal, and list handling of biological or general entity networks. Below, each subtopic of its documentation provides technical and practical insight, illustrated by concrete scenarios and worked examples derived from comprehensive test coverage.

---

## Description

The `KnowledgeBase` class provides a structured and extensible framework for representing, persisting, and querying data and relationships within a knowledge base. Its design facilitates working with namespaces, flexible registry management, and seamless saving/loading of key state. The class is ideal for managing scientific or highly structured datasets with named relationships and metadata.

### Instantiating a KnowledgeBase

A `KnowledgeBase` instance is created with a directory specifying where knowledge base data and configuration files are stored. Optionally, a namespace can be specified to distinguish among different data spaces or contexts.

**Example:**
```ruby
TmpFile.with_dir do |dir|
  kb = KnowledgeBase.new dir
  assert_nil kb.namespace
end
```
This creates a `KnowledgeBase` without a namespace. After saving and reloading, the namespace remains `nil`, confirming persistence accuracy.

You may also specify a namespace:

```ruby
TmpFile.with_dir do |dir|
  kb = KnowledgeBase.new dir, "Hsa"
  assert_equal "Hsa", kb.namespace
  kb.save

  kb = KnowledgeBase.load dir
  assert_equal "Hsa", kb.namespace
end
```

This workflow (from the test suite) demonstrates how to assign, save, and restore a namespace, validating the correct storage and retrieval sequence.

### Persistence: Saving and Loading KnowledgeBase State

The `save` method persists key aspects of the knowledge base (namespace, registry, entity options, and identifier files) to disk as YAML files inside a configuration directory. These files are named according to the variable (for example, `namespace`, `registry`, etc.).

Correspondingly, the `load` method restores this state from these configuration files. Ensuring that saving and reloading a knowledge base instance results in equivalent internal state.

When rehydrating from disk, you might use the class method `.load`, which accepts a directory (possibly as a symbol, which gets expanded with `Path.setup("var").knowledge_base[...]`) and returns a loaded KnowledgeBase instance.

### Registry, Entities, and Metadata

The `KnowledgeBase` maintains several customizable internal collections:
- `@registry` stores mapping of entity names to information or datafiles.
- `@entity_options` holds options (as indifferent hashes) tied to each entity.
- `@identifier_files` is a list of supporting files.
- `@format` and `@indices` support format interpretation and quick lookup.

### Retrieving Entity Information

The `info(name)` method provides a consolidated summary of a registered item (or relationship) within the knowledge base, returning a hash containing:
- `:source` and `:target` entries (entity endpoints/nodes involved in an association)
- `:source_type` and `:target_type` (entity kinds)
- `:fields` (fields defining the relationship)
- `:source_entity_options` and `:target_entity_options` (options from entity definitions)
- `:undirected` (whether the relationship has no directionality)

This is a convenient way to inspect metadata for a given association within the knowledge base.

### Conclusion

The `KnowledgeBase` class forms the backbone for storing, organizing, and retrieving rich, linked data with persistent, versionable state. It is tailored for scenarios where relationships, namespaces, and contexts are first-class citizens, and where the history and portability of the knowledge base's makeup are central.

Typical use cases revolve around creation with or without namespaces, saving/loading from disk-backed stores, and extracting structured, ready-to-use metadata. The robust test cases for namespace management serve as practical guides for correct API usage and state integrity.

---

## Enrichment

The `KnowledgeBase` class provides a comprehensive framework for managing and interacting with complex knowledge graphs and entity-association registries. This class orchestrates reading, writing, and organizing structured knowledge, focusing on entities, associations, metadata, and their relationships.

### File and Variable Management

The knowledge base persists critical internal state such as the namespace, registry, entity options, and identifier files. This state can be stored and reloaded to/from YAML files located within a configurable directory. The following pattern demonstrates the save and reload usage, handling even the absence of a namespace:

```ruby
TmpFile.with_dir do |dir|
  kb = KnowledgeBase.new dir
  assert_nil kb.namespace
  kb.save

  kb = KnowledgeBase.load dir
  assert_nil kb.namespace
end
```

If a namespace is specified, it is likewise persisted along with the rest of the knowledge base metadata:

```ruby
TmpFile.with_dir do |dir|
  kb = KnowledgeBase.new dir, "Hsa"
  assert_equal "Hsa", kb.namespace
  kb.save

  kb = KnowledgeBase.load dir
  assert_equal "Hsa", kb.namespace
end
```

### Configuration Persistence

Configuration variables—like `namespace`, `registry`, `entity_options`, and `identifier_files`—are automatically saved into the appropriate files under the knowledge base's `config` directory. The `save` and `load` instance methods trigger this process, storing internal instance variables as YAML and restoring them as needed.

### Factory Loader

A class-level `KnowledgeBase.load(dir)` factory builds and initializes a knowledge base from persisted data, accepting both `Symbol` and path-like arguments for convenience.

### Entity and Association Queries

With methods like `info(name)`, the knowledge base allows querying for detailed association metadata, including sources, targets, fields, and directionality, by transparently accessing the registry and entity type options for the specified association.

### Summary

Through its design, the `KnowledgeBase` class ensures:
- Reliable persistence of stateful configuration across sessions
- An extensible registry of entities and their associations
- Namespacing and entity type configuration
- Flexible storage location initialization

These features set the foundation for advanced query and enrichment operations, as described under additional topics, allowing users to manage and interrogate rich networks of associations and knowledge with consistency and ease.

---

## Entity

This section documents the entity-related capabilities of the `KnowledgeBase` class, detailing its support for selection, annotation, translation, and identification of entities within a knowledge base. These functions play a critical role in managing the representation and connection of entities in biological or other domain-centric knowledge graphs.

### Selecting Entities

`KnowledgeBase#select_entities` enables the selection of entities based on knowledge base relationships (edges), appropriately extracting source and target entity sets according to the relationship definition and provided options.

### Entity Options

`KnowledgeBase#entity_options_for` retrieves the configuration options (such as formats or additional metadata) for a given entity type, accommodating per-entity or per-database settings. This is especially valuable for systems with heterogeneous entity representations and requirements.

#### Example: Retrieving Entity Options

```ruby
TmpFile.with_dir do |dir|
  kb = KnowledgeBase.new dir
  kb.register :brothers, datafile_test(:person).brothers, undirected: true
  kb.entity_options = { "Person" => { language: "es" } }
  assert_include kb.entity_options_for("Person"), :language
end
```

In this test, a knowledge base is initialized and configured such that the `"Person"` type has a language option set to `"es"`. The test confirms that the `:language` key is present in the options returned by `entity_options_for`.

### Entity Type Resolution

`KnowledgeBase#source_type` and `#target_type` provide automatic type resolution for the source and target vertices of any registered relationship.

#### Example: Inferring Entity Types

```ruby
TmpFile.with_dir do |dir|
  kb = KnowledgeBase.new dir
  kb.register :brothers, datafile_test(:person).brothers, undirected: true
  kb.register :parents, datafile_test(:person).parents
  assert_include kb.all_databases, :brothers
  assert_equal Person, kb.target_type(:parents)
end
```

This example illustrates registration of databases for "brothers" and "parents", then confirms that the target type for the `:parents` relationship is `Person`.

### Entity Identification

The `KnowledgeBase#identify`, `#identify_source`, and `#identify_target` methods provide translation between symbolic or identifier codes and canonical entity names. Identifier files and translation indices automate these mappings.

#### Example: Entity Identifier Mapping

```ruby
TmpFile.with_dir do |dir|
  kb = KnowledgeBase.new dir
  kb.register :brothers, datafile_test(:person).brothers, undirected: true
  assert_equal "Miki", kb.identify(:brothers, "001")
end
```

In this scenario, the system is able to resolve the identifier `"001"` (presumably a person code) to the canonical name `"Miki"` for the `:brothers` database relationship.

### Entity Annotation and Translation

- `#annotate` uses entity options and formats to annotate entities for use in the knowledge base context.
- `#translate` adjusts entity representations into the expected format, if necessary.

### Dynamic Module Enhancement

`KnowledgeBase#define_entity_modules` dynamically constructs or extends modules representing entity types, integrating identifier mapping capabilities as configured in `entity_options`.

### Advanced Functionality

- Index and translation handling in `#source_index` and `#target_index` allow persistent, namespaced, and extensible entity identification.
- Support for namespaced paths and identifier overlays increases interoperability for distributed or federated knowledge base scenarios.

### Edge Cases and Robustness

- If identifier files are missing or cannot be loaded, identifier lookups degrade gracefully to direct return of the original entity.
- Translation indices are constructed with sensitivity to namespace and database-specific context.

These entity management features allow robust, flexible, and highly-integrated handling of entities in large, complex, and multi-modal knowledge bases. The test suite demonstrates key configuration, mapping, and typing idioms in practice.

---

## List

The `KnowledgeBase` class provides comprehensive support for managing named lists of entities or arbitrary values. Lists can be of different types, such as simple arrays of values, or `AnnotatedArray` objects with specific entity associations. These lists can be created, saved, loaded, enumerated, and deleted, with support for handling different file formats and list types.

### File-level Overview

This file implements the internal mechanisms to manage lists within a `KnowledgeBase` stored on disk, ensuring safe file access, integrity of data, and flexible support for types and extensions.

### Functional Highlights

- **list_file**: Determines the filesystem path for a named list, with support for entity typing and file extensions.
- **save_list**: Persists a list to disk, either as a plain file (for simple lists) or as an annotated TSV file for entity-aware (`AnnotatedArray`) lists.
- **load_list**: Restores a list from disk, intelligently choosing the correct loader depending on format and type, and handling edge cases (e.g., non-existent lists) gracefully.
- **lists**: Enumerates all available lists, grouped by entity type.
- **delete_list**: Removes a list from disk with file-locking for safety.

### Usage and Behavior

#### Saving and Loading Annotated Entity Lists

Lists associated with entities, such as those obtained via subset queries, can be saved and later reloaded with full fidelity:

```ruby
kb = KnowledgeBase.new dir
kb.register :brothers, datafile_test(:person).brothers, undirected: true
kb.register :parents, datafile_test(:person).parents

list = kb.subset(:brothers, :all).target_entity
kb.save_list("bro_and_sis", list)
assert_equal list, kb.load_list("bro_and_sis")
```

Here, a subset of entities is saved and verified to persist correctly.

#### Listing and Deleting Entity Lists

Lists are grouped by their entity type and can be discovered and removed:

```ruby
assert_include kb.lists["Person"], "bro_and_sis"
kb.delete_list("bro_and_sis")
refute kb.lists["simple"]
```

After deletion, the list is removed from the grouping.

#### Simple Lists

The `KnowledgeBase` also handles "simple" lists (plain string arrays):

```ruby
list = ["Miki", "Isa"]
kb.save_list("bro_and_sis", list)
assert_equal list, kb.load_list("bro_and_sis")
assert_include kb.lists["simple"], "bro_and_sis"
kb.delete_list("bro_and_sis")
refute kb.lists["simple"].any?
```

This example verifies saving, listing, and deletion of a simple list type.

### Edge-case Handling

- Attempts to fetch or load a list that doesn't exist raise informative errors: e.g., `raise "List not found #{id}" if path.nil?`.
- If list saving fails, the partial file is deleted to avoid corruption.
- Loading automatically distinguishes between TSV-annotated lists and plain lists.
- Deletes are protected by file locks, ensuring thread/process safety.

### Design Notes

- Entity-specific lists and plain lists are both supported transparently.
- File format is deduced both from entity type and file extension.
- Extensive use of file locks (`Open.lock`) guards modification operations.
- Validation and sanitization of filenames prevent directory traversal exploits.

### Summary

This file provides robust, flexible, and safe list management for the `KnowledgeBase`, supporting a variety of workflows such as entity subset extraction, custom groupings, persistence between sessions, and automation of list curation.

---

## Query

The querying capabilities of the `KnowledgeBase` class enable powerful traversal and extraction of relationships and groupings from structured knowledge data. Via a suite of methods such as `subset`, `children`, `parents`, `all`, and `neighbours`, users can specify entity relationships, filter connections, and retrieve meaningful associations.

### Query Fundamentals and Direct Usage

The `subset` method is key to extracting relationships between entities. It accepts the name of the relationship, as well as source/target constraints either as arrays or symbolic values such as `:all` to query the entire set. Options may also be provided to further customize behavior.

A worked test example illustrates this:

```ruby
matches = kb.subset(:parents, :all)
assert_include matches, "Clei~Domingo"

matches = kb.subset(:parents, target: :all, source: ["Miki"])
assert_include matches, "Miki~Juan"
```

Here, by loading name-indexed connections (e.g., `:parents`), users can retrieve all matching relationships, or restrict the search to only those originating from a given source (like `"Miki"`).

### Children and Parents Traversal

`children` and `parents` provide semantic access to downstream and upstream relationships, respectively. For example:

```ruby
assert_include kb.children(:parents, "Miki").target, "Juan"
assert_include kb.children(:brothers, "Miki").target, "Isa"

parents = matches.target_entity

assert_include parents, "Juan"
assert Person === parents.first
assert_equal "en", parents.first.language
```

Here, the `children(:parents, "Miki")` call retrieves entities for which "Miki" is a parent, while `children(:brothers, "Miki")` explores undirected sibling relations.

These associations also support automatic enrichment with properties defined in `entity_options` (as seen with the custom language attribute).

### Entity Attribute Resolution

Entity instances returned (for example, from `.target_entity` or `.first.source_entity`) are automatically instantiated with options derived from their type and the registered association. As demonstrated:

```ruby
assert_equal "en", parents.first.language

matches = kb.subset(:brothers, target: :all, source: ["Miki"])
assert_equal "es", matches.first.source_entity.language
```

This ensures metadata such as language preferences propagate correctly, a feature useful for multilingual or annotated data sources.

### The `all` Method

To list all available entities in a registered relationship, use `all(name)`:

```ruby
assert_include kb.all_databases, :brothers
```

### Directionality and Undirected Relationships

The query API handles both directed and undirected relations. In the example, `:brothers` is registered with `undirected: true`, and the `neighbours` or `subset` queries respect this directionality.

### Summary

The `KnowledgeBase::Query` interface provides rich methods for traversing, querying, and extracting information from entity networks. It supports flexible filtering, semantic directionality, and option-driven enrichment, as shown by the thorough, attribute-aware usage in the test suite. This makes it suitable for knowledge graph traversal, annotation-rich entity extraction, and constructing dynamic relational datasets.

---

## Registry

The `KnowledgeBase` class manages the structure, persistence, registration, and retrieval of associations and entities in a knowledge-oriented system. It provides mechanisms to organize datasets, define registries, and facilitate the loading and saving of knowledge bases.

### Initialization, Persistence, and Namespacing

A `KnowledgeBase` is initialized with a directory for storage and an optional namespace:

```ruby
kb = KnowledgeBase.new dir
# By default, the namespace is nil if not provided

kb = KnowledgeBase.new dir, "Hsa"
# The namespace is set to "Hsa"
```

The namespace, once set, is saved and loaded along with other KB parameters. Usage in code demonstrates this:

```ruby
kb.save
# ... Later
kb = KnowledgeBase.load dir
assert_equal "Hsa", kb.namespace
```

If a namespace isn't specified, it remains `nil` throughout save/load cycles.

### Persistence Mechanisms

A `KnowledgeBase` object supports both manual and automatic saving and loading of its key variable state. Config variables such as `namespace`, `registry`, `entity_options`, and `identifier_files` are serialized in YAML format and stored under the `config/` directory within the KB directory. The methods `save_variable` and `load_variable` manage variable-specific save/load, while the `save` and `load` methods handle all relevant variables in bulk.

Upon calling:

```ruby
kb.save
```

All config variables are written out. They can later be re-read using:

```ruby
kb.load
```

or, by creating a new knowledge base and loading from disk:

```ruby
kb = KnowledgeBase.load dir
```

This ensures seamless ongoing usage and continuity across restarts.

### Registry Integration and Database Management

Registration of datasets (called "databases" in this context) in a `KnowledgeBase` is handled via the `register` method, optionally accepting a file or a code block:

```ruby
kb.register :brothers, brothers
```

Once registered, the dataset name (`:brothers`) appears in the list from `all_databases`:

```ruby
assert_include kb.all_databases, :brothers
```

You can query which database files are present in the KB directory using `present_databases`, and retrieve database files or options by name.

When identifier mappings (for alias resolution or entity matching) are needed, you can register them as shown:

```ruby
identifiers = TSV.open(identifier_file, sep: ",", type: :single)
kb.register :brothers, brothers, identifiers: identifiers
```

The registry system ensures these options are attached and considered during index generation and lookups.

### Indexes and Information Lookup

The KB provides high-level structural introspection for databases via the `info` method, which compiles metadata such as source/target entities, field names, and connection directionality:

```ruby
info = kb.info(:brothers)
# info[:source], info[:target], info[:fields], etc.
```

This allows clients to discover relationships and structure dynamically.

### Design Concepts and Extensibility

- The directory associated with every KB is managed as a `Path` object (see `@dir = Path.setup(dir.dup)`).
- Entity options and registry items are managed using `IndiferentHash` for flexible symbol/string keys.
- State is stored YAML-encoded and may be extended using config files as the system grows.
- Registration can be from files or code blocks, enabling data generation or transformation on-demand.
- The API accommodates flexible lookup and options overriding for each registered database.

### Summary and Usage

A `KnowledgeBase` is designed to be the core abstraction for structured, persistent, registry-driven knowledge storage and retrieval. It supports:

- Initialization with or without a namespace.
- Saving and loading of critical state to disk.
- Flexible registration, lookup, and registry querying.
- Metadata introspection on registered databases.
- Support for dictionary/identifier files for custom alias resolution.

#### Example Workflows

1. **Without namespace:**

   ```ruby
   kb = KnowledgeBase.new dir
   assert_nil kb.namespace
   kb.save
   kb = KnowledgeBase.load dir
   assert_nil kb.namespace
   ```

2. **With namespace:**

   ```ruby
   kb = KnowledgeBase.new dir, "Hsa"
   assert_equal "Hsa", kb.namespace
   kb.save
   kb = KnowledgeBase.load dir
   assert_equal "Hsa", kb.namespace
   ```

3. **Register a dataset and verify registry:**

   ```ruby
   brothers = datafile_test(:person).brothers
   kb = KnowledgeBase.new dir
   kb.register :brothers, brothers
   assert_include kb.all_databases, :brothers
   ```

4. **Registering with identifiers file and querying index:**

   ```ruby
   kb.register :brothers, brothers, identifiers: identifiers
   assert_include kb.get_index(:brothers, source: "=>Initials"), "CC~Guille"
   ```

The `KnowledgeBase` is thus a robust, extensible component suitable for advanced knowledge system engineering, with persistent configuration and registry management as core principles.

---

## Traverse

The `traverse` functionality in the `KnowledgeBase` module enables powerful graph traversal queries, supporting variable assignments, wildcards, conditional filtering, and complex multi-step path finding across registered association datasets. Traversal is managed via the `KnowledgeBase::Traverser` class and exposed as the `KnowledgeBase#traverse` instance method.

### Overview

Traversal is defined as a sequence of rules, each typically of the form:

```
source_entity association target_entity [ - conditions ]
```

- `source_entity` and `target_entity` may be explicit values, lists, or wildcards (notated as `?var`).
- `association` names a registered database or edge type (such as "brothers" or "parents").
- Optional `conditions` provide attribute/value filters for matched links.
- Rules can also express assignments or accumulation blocks for advanced use cases.

### Basic Example

A straightforward usage finds all "brothers" of an entity "Miki" using a single rule, assigning results to the wildcard `?1`.

```ruby
rules = []
rules << "Miki brothers ?1"
res =  kb.traverse rules
assert_include res.first["?1"], "Isa"
```

This pattern recurs for diverse associations and with more complex wildcards:

```ruby
rules = []
rules << "Miki parents ?1"
entities, paths =  kb.traverse rules
assert_include paths.first.first.info, "Type of parent"
```

Setting up the `KnowledgeBase`, registering associations, and invoking `traverse` as above allows users to walk arbitrary associations dynamically.

### Multi-step Traversal

Traversal rules can chain across multiple associations, passing wildcards to accumulate paths through the knowledge graph:

```ruby
rules = []
rules << "Miki marriages ?1"
rules << "?1 brothers ?2"
res =  kb.traverse rules
assert_include res.first["?2"], "Guille"
```

Here, the traversal finds "Miki's" marriage partners, then discovers the brothers of those partners.

### Conditional Filtering

Rules can include filtering based on attributes associated with the links in the database:

```ruby
rules = []
rules << "Miki parents ?1 - 'Type of parent=father'"
entities, paths =  kb.traverse rules
assert_equal entities["?1"], ["Juan"]
```

Only parents for which the `Type of parent` is `'father'` are matched here.

### Target Assignment and Translation

Assignment statements allow entities matching particular query patterns to be named and referenced in subsequent traversal rules. Example:

```ruby
rules = []
rules << "?target =brothers 001"
rules << "?1 brothers ?target"
res =  kb.traverse rules
assert_include res.first["?1"], "Isa"
assert_include res.first["?target"], "Miki"
```

Here `?target` is assigned as those who are brothers of "001", and then further traversals can reference this variable.

### Accumulation Blocks

For more sophisticated workflows, traverse rules also support accumulator blocks (delimited by `{}`) to constrain multiple rules within variable assignments, facilitating complex pattern matches. This enables queries such as finding all entities that share certain properties for two different targets:

```ruby
rules_str=<<-EOF
?target1 =gene_ages SMAD7
?target2 =gene_ages SMAD4
?target1 gene_ages ?age
?target2 gene_ages ?age
?1 gene_ages ?age
EOF
rules = rules_str.split "\n"
res =  kb.traverse rules
assert_include res.first["?1"], "MET"
```

Or with accumulator syntax:

```ruby
rules_str=<<-EOF
?target1 =gene_ages SMAD7
?target2 =gene_ages SMAD4
?age{
  ?target1 gene_ages ?age
  ?target2 gene_ages ?age
}
?1 gene_ages ?age
EOF
rules = rules_str.split "\n"
res =  kb.traverse rules
assert_include res.first["?1"], "MET"
```

### Handling Wildcards and Inter-database Queries

Wildcards can also apply to database names (`?db`), allowing rules to traverse across multiple registered datasets for discovery:

```ruby
rules = []
rules << "SMAD4 ?db ?1"
res =  kb.traverse rules
```

### Return Values

The `#traverse` method returns a tuple: `[assignments, paths]`

- `assignments` is a hash mapping variable names (wildcards) to arrays of matched entities.
- `paths` is a collection of the actual association paths traversed.

### Edge Cases and Behaviors

- If an explicit namespace is not set, the traversal still functions but returns only non-namespaced matches.
- Traversals correctly support both directed and undirected relationships, as set during registration.
- Assignments, conditionals, and pathfinding logic properly deduplicate and match against the underlying entity data.

### Summary

The traverse subsystem is a flexible "query language" for the `KnowledgeBase`, supporting single and multi-step queries, attribute filtering, assignment, advanced pattern matching, and inter-database querying. For real usage patterns, refer to full test examples in `test/scout/knowledge_base/test_traverse.rb`.

---

This comprehensive documentation covers all major facets of the `KnowledgeBase` class and its subsystems, including entity and registry management, persistent state, flexible querying, list handling, and advanced traversal. All examples, behaviors, and design notes are supported by real tests and code usage patterns, ensuring developer confidence for robust, production use.