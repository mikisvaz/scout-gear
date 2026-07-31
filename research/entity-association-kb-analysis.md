# Investigation: Entity, Association, and KnowledgeBase Systems

> **Non-normative.** This document is a working investigation with
> implementation details, code exploration notes, and hypotheses. Refer to
> `doc/developer/` for maintained architectural documentation.

## Overview

The Entity → Association → KnowledgeBase stack provides typed identifiers,
relationship representation, and a query engine for traversing graphs of
relationships between typed entities.

```
Entity (typed identifiers with properties)
   ↓
Association (source ~ target + info fields)
   ↓
KnowledgeBase (registry + index + query + traversal)
```

## Entity system

### Core concept

An Entity is a String (or array of Strings) annotated with type
information. The type is registered via `Entity.formats`, a global registry
mapping type names to Entity modules. For example:

```ruby
module Gene
  extend Entity
  property :length => :single do
    sequence.length
  end
end
```

Here `Gene` is the Entity module. When `Entity.formats["Ensembl Gene ID"] = Gene`
is set, any string annotated as an "Ensembl Gene ID" becomes a `Gene` and
gains access to the `length` property.

### Format registry

`Entity.formats` is a `FormatIndex` (subclass of Hash) mapping format
strings to Entity modules. A format string is a human-readable identifier
type, e.g., `"Ensembl Gene ID"`, `"UniProt Entry Name"`.

The `Entity::FormatIndex` overrides `find` to support format-format lookup:
given a field name, it can resolve which Entity module it corresponds to.

### Property type system

Properties are defined with `property name => type, &block`. The type
controls how the property behaves when called on a single entity vs. an
array of entities:

| Type | Behavior |
|------|----------|
| `:single` | Only works on a single entity. Called on an array, raises error. |
| `:array` | Only works on an array. Called on a single entity, raises error. |
| `:multiple` | Works on an array. Internally calls the single-entity version for each item. |
| `:both` (default) | Works on both single and array. The same block handles both cases. |
| `:single2array` | Like `:single` but auto-wraps result in array when called on array. |
| `:array2single` | Like `:array` but auto-handles single entity as one-element array. |

Internally, methods are named `_single_<name>`, `_ary_<name>`, or
`_multi_<name>` depending on the type. The public method dispatches to the
appropriate internal method.

### Property persistence

Properties can be persisted via `persist :property_name, type: :yaml` (or
any other type). This is handled by `Entity::Property.persist`, which uses
`Persist.persist` under the hood. The cache key is derived from the property
name and the entity ID.

### Identifier translation

Entities can translate between formats via the `to` method. This uses
identifier files (TSV files mapping between formats). The
`Entity::Identifiers` module provides:
- `Entity::Identifiers.index(file, ...)` — build an index from a file
- `entity.to("New Format")` — translate the entity to a new format

Translation is lazy: the index is built on first use and cached via
`Persist.tsv`.

### Entity setup

`Entity.prepare_entity(entities, format, options)` is the factory method
that:
1. Looks up the Entity module for the given format
2. Calls `mod.setup(entity, params)` to annotate the string(s)
3. Extends with `AnnotatedArray` if the input is an array

## Association system

### Core concept

An Association represents a relationship: `source ~ target` plus optional
information fields. It is built from a TSV where the key field contains
`source~target` pairs (joined by `~`) and the value fields contain
information about the relationship.

### Field specification

`Association.fields.rb` handles the flexible specification of source and
target fields. The `extract_specs` method resolves:
- `source:` and `target:` options (can be field names, positions, or entity
  format types)
- `source_format:` and `target_format:` (entity format translation)
- Auto-detection: if source/target not specified, defaults to key_field and
  first value field

The specification syntax supports:
- `"FieldName"` — direct field name
- `"FieldName=~Format"` — field name with desired output format
- `"EntityFormat"` — resolve by entity type (looks up all fields of that type)
- `Numeric` — field position

### Index building

`Association.index(file, ...)` builds a persisted TSV index:
1. Parse source/target specifications from the file's header
2. Build a Transformer that reads the source TSV
3. For each row, extract source, target, and info fields
4. Write `source~target => [info_fields]` into the index
5. The index is persisted via `Persist.tsv`

The resulting index TSV has:
- Key field: `source~target`
- Value fields: `[target, *info_fields]`
- Extended with `Association::Index` module

### AssociationItem

`AssociationItem` is an Entity that wraps a single association row. It is
set up via `AssociationItem.setup(matches, kb, database_name, reverse)`.

Key properties:
- `source_entity`, `target_entity` — the entities at each end
- `source`, `target` — the raw identifiers
- `name` — `"source~target"` string
- `reverse` — whether this is a reverse association

The `database` and `knowledge_base` annotations link the item back to its
origin.

### Reverse associations

Associations can be queried in reverse. When `reverse: true`, source and
target are swapped. The KnowledgeBase handles this transparently via
`children`/`parents` methods.

## KnowledgeBase system

### Registry

`KnowledgeBase#register(name, file, options)` registers a database:
- `name` — database name (used in queries)
- `file` — source file (or block for dynamic databases)
- `options` — passed to `Association.index`

Registered databases are stored in `@registry` as `[file, options]` pairs.

### Index management

`KnowledgeBase#get_index(name)` builds (or loads) the Association index for
a registered database. The index is persisted under
`var/knowledge_base/<namespace>/<name>.database`.

`KnowledgeBase#get_database(name)` returns the raw TSV (without the
Association index wrapper).

### Query API

`KnowledgeBase#query(name, source_entities, target_entities)` returns an
array of AssociationItem objects matching the query.

Methods:
- `children(name, entities)` — entities that are targets of the given sources
- `parents(name, entities)` — entities that are sources of the given targets
- `subset(name, source, target)` — all associations matching source AND target

### Traversal DSL

`KnowledgeBase#find` and the `Traverser` class (`traverse.rb`) provide a
graph-traversal DSL with wildcard and list support:

```ruby
kb.find "?gene", "Database1", "?protein"
kb.find "?protein", "Database2", "?pathway"
```

The Traverser:
1. Parses each rule: `source database target`
2. `?` prefix = wildcard (variable)
3. `:` prefix = list reference (loaded via `kb.load_list`)
3. Uses forward propagation: resolves first rule, assigns wildcards, then
   uses assignments to constrain subsequent rules
4. `clean_matches` ensures consistency across rules

The `_fp` (forward propagation) method iterates rules, resolving each based
on current assignments. The `_bp` (backward) variant exists but forward
propagation is the primary strategy.

### Entity integration

The KnowledgeBase annotates query results with entity types:
- `kb.annotate(entities, type, database)` — prepares entities with format
  translation and entity options
- `kb.translate(entities, type)` — applies format translation if needed
- Entity options (organism, namespace, identifiers) are merged from KB and
  database-level options

### Lists

`KnowledgeBase#save_list`, `load_list`, `lists`, `delete_list` manage named
entity lists. Lists can be:
- Simple text files (one ID per line)
- TSV files with annotation data (for AnnotatedArray entities)

Lists are stored under `var/knowledge_base/<namespace>/lists/<type>/<id>`.

## Design observations

1. **Entity as annotated string** — The core insight is that an Entity is
   just a String with metadata. No separate object hierarchy; the type
   information is attached via annotations. This is the Scout philosophy of
   "annotated objects" applied uniformly.

2. **Association as TSV transform** — Associations are not a new data
   structure; they are a transformation of a regular TSV into a specific
   key format (`source~target`). The Association module is a thin layer over
   TSV operations.

3. **KnowledgeBase as registry + index** — The KB doesn't store data; it
   manages a registry of sources and builds persisted indexes on demand.
   This lazy-evaluation pattern is consistent with Scout's caching-first
   philosophy.

4. **Property dispatch system** — The property type system (`:single`,
   `:array`, `:multiple`, `:both`) elegantly handles the common case where
   an operation should work on both single entities and arrays without
   requiring separate method definitions.

5. **Wildcard traversal** — The Traverser's wildcard-based forward
   propagation is a mini constraint-propagation engine. It's simple but
   sufficient for most graph traversal needs.

## Warnings

- `Entity::FORMATS` is a global mutable registry. If multiple workflows
  define the same format, the last definition wins. There is no namespacing.
- The `Association.fields` extraction logic is complex and has many special
  cases. The `identify_entity_format` fallback can mask configuration
  errors by silently using the wrong field.
- The Traverser's `clean_matches` uses `.partition("~")` which is fragile
  if entity IDs contain `~`.
- Property persistence uses the entity ID as part of the cache key, which
  means format-translated entities share the same cache as their original.
  This can lead to incorrect cached results if a property depends on the
  format.
- The `NilFloat = -999.999` sentinel in float serialization (from
  TSVAdapter) can collide with real data values.
