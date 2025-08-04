# Entity

The `Entity` module is a powerful foundation for building robust, annotated, property-rich objects with flexible format, identifier, and conversion support. It provides a compositional system that allows modules to gain entity-like behaviors through extension, including dynamic format resolution, persistent and cacheable property management, support for identifier mapping and translation, and more. This robust system is especially useful for domain modeling where values, their formats, and translations between representations are core concerns.

---

## Module Overview

Extending a module or class with `Entity` brings in core capabilities such as:

- Declarative, persistent, and cacheable properties (`Entity::Property`).
- Flexible format assignment and discovery (`Entity::Format`).
- Identifier management and cross-format translation (`Entity::Identifiers`).
- Value object utility methods (`Entity::Object`).
- Enhanced array support for named, annotated content (`Entity::NamedArray`).
- Automatic annotation and introspection support.

When a module extends `Entity`, it undergoes an internal setup altering its instance and class-level behaviors to support entity-style annotation, property declaration, and more. For example:

```ruby
module EmptyEntity
  extend Entity
end
```

Even empty modules (without custom properties or formats) can function as valid entities and offer robust, safe instantiation.

---

## Format

The Entity format system (`Entity::Format`) enables dynamic assignment, indexing, and resolution of formats for entity types. Entities can assign canonical names as their format, register multiple names or aliases, and use the centralized `formats` registry for flexible and variant lookup.

Format matching is robust, supporting lookups by exact and parenthesized names:

```ruby
index = Entity::FormatIndex.new
index["Ensembl Gene ID"] = "Gene"
assert_equal "Gene", index["Ensembl Gene ID"]
assert_equal "Gene", index["Transcription Factor (Ensembl Gene ID)"]

Entity::FORMATS["Ensembl Gene ID"] = "Gene"
assert_equal "Ensembl Gene ID", Entity::FORMATS.find("Ensembl Gene ID")
assert_equal "Ensembl Gene ID", Entity::FORMATS.find("Transcription Factor (Ensembl Gene ID)")

assert_equal "Gene", Entity::FORMATS["Ensembl Gene ID"]
assert_equal "Gene", Entity::FORMATS["Transcription Factor (Ensembl Gene ID)"]
```

When creating or wrapping instances, `Entity.prepare_entity` ensures that values are converted, duplicated, and annotated as necessary, aligning instance representation with the intended format, even supporting operations on strings, arrays, and numerics when appropriate.

Typical instantiation involves the `setup` method:

```ruby
person = Person.setup("Miguel", 'es')
assert_equal "Hola Miguel", person.salutation

person.language = 'en'
assert_equal "Hi Miguel", person.salutation
```

Empty entities are also supported:

```ruby
refute EmptyEntity.setup("foo").nil?
```

This shows entities can be meaningfully constructed even when minimal.

---

## Identifiers

Through `Entity::Identified`, modules gain flexible identifier translation, file-based mapping, and namespace support. Entities can declare and use external files storing mappings between identifier formats (`Name`, `Alias`, `ID`, etc.), and translate seamlessly:

```ruby
Person.add_identifiers datafile_test(Entity::Identified::NAMESPACE_TAG + '/identifiers'), "Name", "Alias"
miguel = Person.setup("Miguel", namespace: :person)
miguel.to("Alias") # => "Miki"
```

Arrays of identifiers are equally supported:

```ruby
Person.setup(["001"], :format => 'ID', namespace: :person).to("Name") # => ["Miguel"]
```

Error handling is robust: requests for translations without proper configuration or namespace annotation raise errors, ensuring correctness:

```ruby
miguel = Person.setup("Miguel")
assert_raise do
  miguel.to("Name")
end

miguel = PersonWithNoIds.setup("Miguel", namespace: :person)
assert_raise do
  miguel.to("Name")
end
```

Further details:

- Identifier files can be discovered via `Entity.identifier_files(field)`.
- Conversion supports both direct and symbolic (e.g., `:name`, `:default`) access.
- Mappings are namespace-aware and raise informative errors on missing data.

---

## NamedArray

The `Entity::NamedArray` module enriches array-like objects with named-key access, supporting retrieval and implicit entity conversion by semantic name:

```ruby
a = NamedArray.setup(["a", "b"], %w(SomeEntity Other))
assert a["SomeEntity"].respond_to?(:prop)
```

Here, `a["SomeEntity"]` looks up the value by field name and passes it through `Entity.prepare_entity`, ensuring correct entity-type behavior and properties become available.

- If the key does not exist, `nil` is returned.
- Integer keys are supported, as are standard positional lookups.

Use `NamedArray` when you need flexible, safe access to collection items by field name with entity semantics.

---

## Object Utilities

`Entity::Object` provides introspective and utility methods underpinning entity composition and inheritance:

- `entity_classes`: Returns all entity modules in the annotation ancestry.
- `base_entity`: Returns the most fundamental entity type in the chain.
- `_ary_property_cache`: Provides a per-object property cache.
- `all_properties`: Aggregates all available properties from the hierarchy.

These methods are vital for managing and inspecting complex entity compositions.

---

## Property

The `Entity::Property` module allows concise declaration and management of properties on entities, with strong support for:

- Single-value, array-wide, and multiple-item properties.
- Persistent and cacheable property methods with transparent caching.
- Annotated array and multiple-annotation handling.
- Purge support to remove entity enhancements from values.

Examples from the test suite:

```ruby
module ReversableString
  extend Entity

  property :reverse_text_ary => :array do
    $count += 1
    self.collect{|s| s.reverse}
  end

  property :reverse_text_single => :single do
    $count += 1
    self.reverse
  end

  property :multiple_annotation_list => :multiple do 
    $processed_multiple.concat self
    res = {}
    self.collect do |e|
      e.chars.to_a.collect{|c| ReversableString.setup(c) }
    end
  end
end

a = ["String1", "String2"]
ReversableString.setup(a)

assert_equal "2gnirtS", a.reverse_text_ary.last

string = 'aaabbbccc'
ReversableString.setup(string)
assert_equal string.length, string.annotation_list.length
```

Features include:

- Type discrimination for `:array`, `:single`, `:both`, and `:multiple` properties.
- Persistent properties which can be enabled, unpersisted, or cached.
- Purging support: `purge` removes properties enhancements from objects.
- All-defined properties retrievable for both the module and instances.

Edge-case attention includes:

- Array vs single context handling.
- Multiple annotation aggregation.
- Defensive handling of caches and property definitions.

---

## Summary

The `Entity` system is a compositional, extensible foundation for developing rich value objects in Ruby, with strong support for:

- Format discovery and registry,
- Identifier mapping and translation infrastructure,
- Persistent, cacheable, and array-aware properties,
- Seamless annotation and type conversion,
- Array extension for named-key and automatic entityification,
- Introspection on entity hierarchy and properties.

This powerful toolkit is tested for a wide spectrum of behaviors, including advanced and edge-case scenarios in property definition, format and identifier handling, extensive caching, and more.