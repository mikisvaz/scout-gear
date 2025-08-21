# Entity

Entity is a lightweight system to turn plain Ruby values (strings, arrays, numerics) into annotated, behavior-rich “entities.” It layers on top of Annotation and provides:

- A module-level DSL to define “properties” (methods) for entities and arrays of entities.
- Format mapping and identifier translation between formats (via TSV indices).
- Automatic conversion of NamedArray field values into the appropriate entity type.
- Optional persistence for property results (including annotation lists) using Persist.
- Array-aware property execution with smart caching and support for multi-return computations.

Sections:
- Getting started and core concepts
- Formats and automatic conversion
- Properties: types, array semantics and persistence
- Identifier translation (Entity::Identified)
- Integration with NamedArray and TSV
- Introspection helpers
- Examples

---

## Getting started and core concepts

Define a new entity type by extending Entity in a module. The module becomes the “entity class” for values you annotate with it.

```ruby
module ReversableString
  extend Entity

  property :reverse_text => :single do
    self.reverse
  end
end

s = ReversableString.setup("String1")
s.reverse_text  # => "1gnirtS"
```

Key facts:
- Extending Entity decorates the module with Annotation and Entity::Property capabilities.
- Entity.setup(value, format: ..., namespace: ...) annotates the value with this entity module (and any extra metadata).
- Entities can also be arrays: pass an array to setup to make an AnnotatedArray; properties can be defined to act on the array or per-item.

---

## Formats and automatic conversion

Entity supports “formats” to describe the logical identifier type of a value (e.g., “Ensembl Gene ID”, “Name”). Formats are globally mapped to entity modules using a tolerant index:

- Set formats accepted by the entity:
  ```ruby
  module Gene
    extend Entity
    self.format = ["Ensembl Gene ID", "Alias", "Name"]
  end
  ```

- Global registry:
  - Entity.formats is a FormatIndex (case-aware, tolerant finder). It can match strings like “Transcription Factor (Ensembl Gene ID)” to “Ensembl Gene ID”.
  - Entity.formats[format_name] ⇒ entity module.

Automatic conversion when reading from tables:
- NamedArray fields return values wrapped as entities if there is a matching format. See Integration with NamedArray.

Manual preparation:
- Entity.prepare_entity(value, field, options = {}) returns a value annotated with the entity for that field if a matching format is known:
  ```ruby
  Entity.prepare_entity("ENSG000001", "Ensembl Gene ID")  # wraps into the entity registered for that format
  ```

---

## Properties: types, array semantics and persistence

Define behaviors (methods) using the property DSL. A property can target:
- :single — defined for a single entity.
- :array — defined for an array of entities (takes the array as self).
- :multiple — batch property for arrays that computes all missing per-item results at once and returns a mapping/array; Entity handles filling per-item caches.
- :both — define a method directly that should work for both single and array (default).
- Interface adapters:
  - :single2array — defined for single values, but expose an array facade.
  - :array2single — defined for arrays, but expose single-return facade.

Examples:

```ruby
module ReversableString
  extend Entity

  # Operates on single entity
  property :reverse_text_single => :single do
    self.reverse
  end

  # Operates on an array and returns per-item values
  property :reverse_text_ary => :array do
    self.collect { |s| s.reverse }
  end

  # Both single and array supported by a single method
  property :reverse_both => :both do
    if Array === self
      self.collect(&:reverse)
    else
      self.reverse
    end
  end

  # Batch compute for arrays (multiple)
  property :multiple_annotation_list => :multiple do
    # Return either an Array aligned with input indices or a Hash {item => result}
    self.collect { |e| e.chars } # e.g., list of char arrays
  end
end
```

Array semantics and caching:
- When you call an array property from an element (item.reverse_text_ary), Entity uses the container’s cached result via an internal _ary_property_cache to avoid recomputing per element.
- For :multiple, Entity runs the computation once for the whole array, caches, and dispatches results to the items that requested it (even across partially overlapping arrays).

Persistence for properties:
- Mark any property as persisted to cache its result across runs/filesystems:

```ruby
ReversableString.persist :reverse_text_single, :marshal
ReversableString.persist :reverse_text_ary, :array, dir: "/tmp/entity_cache"
ReversableString.persist :annotation_list, :annotation, annotation_repo: "/path/to/repo.tch"
```

- persist(name, type=:marshal, options={})
  - type can be any Persist serializer or special:
    - :annotation or :annotations — store annotation objects via Persist.annotation_repo_persist (Tokyo Cabinet repo), with option :annotation_repo pointing to the repo path.
    - :array, :marshal, etc.
  - options default to:
    - persist: true
    - dir: Entity.entity_property_cache[self.to_s][name] (default cache under var/entity_property/<Entity>/<property>)
- persisted?(name), unpersist(name) — manage persisted registration.
- Internally, Entity::Property.persist wraps property execution inside Persist.persist (or annotation_repo_persist) and keys it by entity id.

Notes:
- Entity.ids are derived from Annotation ids (Annotation::AnnotatedObject#id).
- Persisted array returns are validated against the current array call sites to extract per-item results correctly.

---

## Identifier translation (Entity::Identified)

For entities that can translate between identifier formats, include Entity::Identified and register identifier sources.

Register identifier files:
- add_identifiers(file_or_tsv, default_format=nil, name_format=nil, description_format=nil)
  - file can be a Path/filename (with optional NAMESPACE placeholders) or a TSV instance.
  - This sets:
    - identity formats on the entity (formats accepted),
    - default format (:default),
    - name format (:name),
    - description format (not used directly in core, but available).

Namespace placeholder:
- Use “NAMESPACE” in file paths to be replaced dynamically using the entity instance’s namespace annotation.
  - If your files include NAMESPACE and the value is not provided on the entity, those files are skipped with a warning.

Translate between formats:
- to(target_format) property is auto-defined for Identified entities.
  - target_format can be a literal format name, :name (-> name_format), or :default.
  - Works on single entities or arrays; on arrays returns an array aligned with input order.
  - Example:
    ```ruby
    module Person
      extend Entity
    end
    Person.add_identifiers("/data/#{Entity::Identified::NAMESPACE_TAG}/identifiers", "Name", "Alias")

    miguel = Person.setup("001", format: "ID", namespace: :person)
    miguel.to("Alias")   # => "Miki"
    miguel.to(:name)     # => "Miguel"
    ```

Identifier indexes:
- Entity builds and caches TSV.translation_index from identifier files via Persist.memory, keyed by [entity_type, source_format, target_format].
- Call identifier_index(target_format, source_format=nil) to get the TSV index.
  - source_format defaults to the entity’s current format; if not found, Entity retries without specifying source.

Introspection:
- Entity.identifier_files(field) — class method returning the list of TSVs involved in a format for entities that include Identified.

---

## Integration with NamedArray and TSV

Entity values are automatically prepared when accessing NamedArray fields:

- NamedArray#[](key) is overridden to call Entity.prepare_entity(v, key), so if a field name is a recognized format (or carries it in parentheses, e.g., “Gene Name (Ensembl Gene ID)”), the returned cell value is wrapped as an entity.

Example:
```ruby
module SomeEntity; extend Entity; self.format = "SomeEntity"; end

row = NamedArray.setup(["a", "b"], %w(SomeEntity Other))
row["SomeEntity"].respond_to?(:all_properties)  # => true
```

This makes TSV rows entity-aware when you deserialize via TSV.open; NamedArray instances become rich objects with entity behaviors available per column.

---

## Introspection helpers

Entity::Object adds convenience to every annotated entity:

- entity_classes — list of Entity modules applied (from Annotation).
- base_entity — the last Entity in annotation_types, i.e., the primary one.
- all_properties — list of property names available across entity modules.
- _ary_property_cache — internal cache used to memoize array property evaluations for items.

The Entity module itself exposes:
- Entity.formats — global FormatIndex of format name → entity module, with tolerant lookup (find handles strings with extra decorations).
- Entity.prepare_entity(value, field, options={}) — utility to wrap a value or array into an entity based on format mapping.

---

## Examples

Define a property-rich entity and use it on values and arrays:

```ruby
module ReversableString
  extend Entity

  property :reverse_text_single => :single do
    self.reverse
  end

  property :reverse_text_ary => :array do
    self.collect { |s| s.reverse }
  end

  # Persist selected properties
  persist :reverse_text_single, :marshal
  persist :reverse_text_ary, :array
end

# Single
s = ReversableString.setup("String1")
s.reverse_text_single  # => "1gnirtS"

# Array
arr = ReversableString.setup(["String1", "String2"])
arr.reverse_text_ary       # => ["1gnirtS", "2gnirtS"]
arr[1].reverse_text_ary    # uses cached array result; returns "2gnirtS"
```

Translate identifiers:

```ruby
module Person
  extend Entity
end

# Identify formats and sources
Person.add_identifiers("/data/#{Entity::Identified::NAMESPACE_TAG}/identifiers.tsv",
                       "Name", "Alias")

Person.setup("001", format: "ID", namespace: :person).to("Alias")   # => "Miki"
Person.setup("001", format: "ID", namespace: :person).to(:name)     # => "Miguel"

list = Person.setup(["001"], format: "ID", namespace: :person)
list.to("Name")  # => ["Miguel"]
```

Automatic entity wrapping from NamedArray/TSV:

```ruby
module Gene; extend Entity; self.format = "Ensembl Gene ID"; end

tsv = TSV.open <<~EOF
#: :sep=" " #:type=:list
#Id Ensembl Gene ID Other
row1 ENSG0001 X
EOF

row = tsv["row1"]
g = row["Ensembl Gene ID"]   # => wrapped into Gene entity (if format registered)
g.all_properties             # => property list for Gene
```

---

## Notes and edge cases

- Entity.prepare_entity duplicates input strings/arrays to avoid mutating caller state; array duplication can be forced per call via dup_array:true.
- For arrays, properties marked :array2single or :single2array adapt their interface between collection and element call sites.
- When using identifiers with NAMESPACE placeholders, ensure you set namespace on entities (Person.setup("001", namespace: :person)) or those files will be ignored.
- Persisted annotation properties (type :annotation) use a Tokyo Cabinet repo; you can supply a repo path via annotation_repo:, or let Persist.annotation_repo_persist create/use a repo by path.

Entity turns plain values into meaningful, behavior-rich objects tailored to your domain (genes, samples, users, etc.), with robust identifier translation and scalable property evaluation/persistence built-in.