## Identifiers

The `Entity::Identified` module adds robust, annotation-driven identifier mapping and translation functionality to Entity modules. This enables seamless transformation between multiple identifier formats (“Name”, “ID”, “Alias”, etc.), discovery and management of identifier files, and caching for efficient lookups. The system supports annotation-based namespaces, custom file resolution, and automated property-based conversion.

### Overview

By including `Entity::Identified`, an entity type can:

- Register mapping files containing identifier translations using `.add_identifiers`.
- Easily convert between identifier formats at runtime (`#to`, `#name`, `#default`).
- Support both single and array-based identifier values.
- Dynamically resolve, cache, and interpret identifier files, even across namespaces.

### Defining and Using Identifiers

Entities register their translation mappings with `.add_identifiers`, passing the path to a mapping file and specifying primary formats:

```ruby
Person.add_identifiers datafile_test(Entity::Identified::NAMESPACE_TAG + '/identifiers'), "Name", "Alias"
```

Instantiated entities can convert between registered formats:

```ruby
miguel = Person.setup("Miguel", namespace: :person)
assert_equal "Miki", miguel.to("Alias")
```

You can also start with an alternative format and translate:

```ruby
Person.setup("001", :format => 'ID', namespace: :person).to("Alias") # => "Miki"
Person.setup("001", :format => 'ID', namespace: :person).to("Name")  # => "Miguel"
```

For array values, conversion is just as seamless:

```ruby
assert_equal ["Miguel"], Person.setup(["001"], :format => 'ID', namespace: :person).to("Name")
```

### Error Handling and Namespaces

Identifier mappings may require a namespace substitution, especially if files contain placeholders like `NAMESPACE_TAG`. Files with unresolved placeholders are skipped, and a warning is issued.

Attempting to convert without an appropriate namespace (or with a module lacking identifiers) results in an exception:

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

### File and Index Discovery

Find out which files an entity is using for identifier lookups:

```ruby
assert Person.identifier_files.any?
assert Entity.identifier_files("Name").any?
```

### Methods

**Class Methods:**

- `Entity.identifier_files(field)`: Returns all identifier files relevant to an entity or format.
- `.add_identifiers(file, default = nil, name = nil, description = nil)`: Registers a file and associated format names.

**Instance Methods/Properties:**

- `#to(target_format)`: Converts to the given identifier format (or `:name`/`:default` symbol).
- `#name`: Shortcut for name format conversion.
- `#default`: Shortcut for default format conversion.
- All methods work on both scalar and array values.

### Internals and Caching

- Internally, lookups and translations are cached for efficiency, and underlying infrastructures like `identifier_index` attempt to recover from lookup failures (retrying broad-to-narrow resolutions as needed).
- File paths and mappings are interpolated per-namespace if needed.

### Test-Driven Scenarios

The robust test suite ensures all error and edge cases function as expected, including:

- Conversion and file resolution with/without namespaces.
- Responses to missing data or lookup failures.
- Proper conversion on arrays and alternate input formats.

### Summary

`Entity::Identified` is the backbone for flexible, scalable, and robust identifier translation in entity-rich modeling scenarios. It facilitates mapping, conversion, and annotation-aware identifier logic, with proven correctness in demanding and edge-case-heavy domains.