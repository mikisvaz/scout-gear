## Entity

The `KnowledgeBase` class offers advanced capabilities for entity management—including selection, type resolution, annotation, and canonical identification—that underpin the representation and traversal of entities in structured knowledge graphs.

### Selecting Entities

The method `KnowledgeBase#select_entities` efficiently extracts sets of source and target entities associated with a particular relationship. This involves resolving appropriate fields based on the registered relationship definition and any supplied options. It supports flexible use of hash keys or symbol aliases, ensuring source and target sets are correctly identified from a provided entity grouping.

### Configuring and Retrieving Entity Options

With `KnowledgeBase#entity_options_for`, users can retrieve configuration options—such as format details or metadata—for any given entity type within the knowledge base. This method accounts for global, per-type, and per-database configuration, ensuring entity behavior (such as display language or mapping strategy) is consistently and hierarchically applied.

#### Example: Retrieving and Verifying Entity Options

```ruby
TmpFile.with_dir do |dir|
  kb = KnowledgeBase.new dir
  kb.register :brothers, datafile_test(:person).brothers, undirected: true
  kb.entity_options = { "Person" => { language: "es" } }
  assert_include kb.entity_options_for("Person"), :language
end
```

This test demonstrates assignment of a custom language option for the `"Person"` entity type. When fetching options for `"Person"`, the managed settings—such as `:language`—are correctly surfaced.

### Resolving Entity Types

`KnowledgeBase#source_type` and `#target_type` provide type inference for the source and target nodes of any registered relationship or database. This ensures that entity queries and annotative routines can work type-agnostically, referencing well-defined Ruby classes or modules for downstream use.

#### Example: Validating Type Inference

```ruby
TmpFile.with_dir do |dir|
  kb = KnowledgeBase.new dir
  kb.register :brothers, datafile_test(:person).brothers, undirected: true
  kb.register :parents, datafile_test(:person).parents
  assert_include kb.all_databases, :brothers
  assert_equal Person, kb.target_type(:parents)
end
```

The test confirms successful retrieval of the target type for the `:parents` relationship after appropriate registration steps.

### Identifier Mapping and Entity Canonicalization

To bridge between local identifiers (like codes or external aliases) and canonical knowledge base entities, `KnowledgeBase` supplies robust mapping via `#identify`, `#identify_source`, and `#identify_target`. These methods use translation indices built from identifier files to translate queried inputs into the canonical, internally consistent entity names.

#### Example: Mapping Identifiers to Canonical Names

```ruby
TmpFile.with_dir do |dir|
  kb = KnowledgeBase.new dir
  kb.register :brothers, datafile_test(:person).brothers, undirected: true
  assert_equal "Miki", kb.identify(:brothers, "001")
end
```

This demonstrates automatic mapping of `"001"` to the canonical `"Miki"` for the registered `:brothers` relationship.

- If identifier data cannot be loaded, entity resolution gracefully degrades to passing through the original input.
- Indexing is sensitive to both namespace and per-database context, accommodating federated or distributed knowledge base structures.

### Annotating and Translating Entities

- `#annotate` uses entity-type configuration and expected formats to add context or attributes to entity sets.
- `#translate` converts entity collections between alternative formats, if required by the knowledge base or downstream logic.

### Dynamic Module and Identifier Enhancement

`KnowledgeBase#define_entity_modules` facilitates dynamic Ruby module creation or extension for each registered entity type, injecting identifier mapping logic and behavior as needed to unify usage and access across diverse codebases.

### Advanced Index and Translation Handling

- `#source_index` and `#target_index` generate fast, persistently cached translation indices for entities, using all known identifier files and overlays.
- Support for namespace-aware file resolution and identifier overlays empowers advanced scientific or multi-tenant contexts.

### Edge-case Handling

- Missing or incomplete identifier files don't raise hard errors; entity lookups simply revert to original names.
- Index construction and annotation auto-disable or fallback based on available metadata, ensuring robustness in heterogeneous or evolving datasets.

---

In sum, entity-centric features within the `KnowledgeBase` enable sophisticated, reliable, and extensible modeling for knowledge systems, as validated by extensive test-driven idioms around type management, identifier mapping, and configuration flexibility.