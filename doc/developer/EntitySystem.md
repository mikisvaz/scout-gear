# Entity System

This document describes the internal architecture of the Entity system.

It is intended for framework contributors who need to understand how
entity types, properties, and identifier translation work internally.

## Overview

The Entity system lets you attach types and computed properties to plain
identifiers (usually Strings). An Entity is not a new class — it's an
annotated String. The annotation carries the entity type, format, and
available properties.

This is built on scout-essentials'
[Annotation](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/AnnotationSystem.md),
which provides the core annotation mechanism.

## Entity definition

An entity type is defined as a Module that extends `Entity`:

```ruby
module Research
  module Gene
    extend Entity

    property :name do
      "Gene #{self}"
    end
  end
  extend Entity
  property :name do
    "Gene #{self}"
  end
end
```

When you call `Gene.setup("ENSG00000141510")`, the String is annotated
in-place with the `Gene` module. The annotation includes:
- `format` — The identifier format (e.g., "Ensembl Gene ID").
- `entity_opts` — Options for property dispatch.

## Property dispatch

Properties are defined with `property :name [, type], &block`. The type
controls how the block is dispatched when `self` is an array of entities.

| Type | Behavior when self is an Array | Behavior when self is a String |
|------|-------------------------------|-------------------------------|
| `:single` (default) | Call block once with the whole array | Call block with the string |
| `:array` | Call block on each element; collect results | Call block with the string |
| `:multiple` | Call block once; expect multiple results | Call block with the string |
| `:both` | Use `:array` for arrays, `:single` for strings | Call block with the string |

The dispatch type affects:
- How the property is invoked when `self` is a collection.
- Whether properties are automatically parallelized.
- How results are collected.

### Property implementation

`property` is implemented using the annotation system:

1. The property name and block are registered in a class-level hash
   (`@properties`) on the entity module.
2. When `setup` is called, the module's properties are made available to
   the annotated object via `define_method` or `method_missing`.
3. When a property is called, the block is executed with `self` set to
   the identifier string.

## Format registry and identifier translation

Each entity type has a `format` — the identifier format it uses (e.g.,
"Ensembl Gene ID", "Associated Gene Name").

### Format declaration

```ruby
module Research
  module Gene
    extend Entity
    format "Ensembl Gene ID"
  end
end
```

The format is stored as an annotation. When translating identifiers, the
entity system looks for identifier files.

### Identifier files

Identifier files follow the convention:
```
var/<namespace>/identifiers/<source_format>%to<target_format>
```

These are TSV files mapping one format to another. The `translate` method
looks up these files:

```ruby
property :symbol do
  translate "Ensembl Gene ID", "Associated Gene Name"
end
```

The `translate` method:
1. Looks for `var/<namespace>/identifiers/Ensembl Gene ID%toAssociated Gene Name`.
2. If not found, tries the reverse (`%to` in the other direction).
3. If still not found, raises an error.

### Identifier file discovery

The `identifier_files` annotation lists paths where identifier files are
searched. These can be extended:

```ruby
Gene.identifier_files << "path/to/custom_identifiers.tsv"
```

## Persistence of entity properties

Entity properties can use persistence to avoid recomputation:

```ruby
property :expression do
  persist :expression do
    TSV.open("expression_data.tsv")[self]
  end
end
```

The `persist` helper wraps the block in `Persist.persist`. The persistence
key is derived from the entity type, format, and property name.

## Entity in workflows and the KnowledgeBase

### EntityWorkflow

The `EntityWorkflow` mixin integrates entities with workflows. When a
workflow extends `EntityWorkflow`, entity properties become available as
workflow helpers. This allows task bodies to call entity properties
directly.

### KnowledgeBase integration

Entities integrate with the KnowledgeBase through properties that query
associations:

```ruby
property :partners do
  kb = KnowledgeBase.get("Research")
  kb.find(:ppi, self, :p)
end
```

The KnowledgeBase uses entity types to resolve field specifications and
enable relationship traversal.

## Extension points

### Adding a new property dispatch type

1. Add the type to the dispatch logic in `Entity.property`.
2. Update the property resolution to handle the new type for arrays vs
   singles.

### Custom identifier translation

If identifier files don't meet your needs, you can override `translate`:

```ruby
module Research
  module Gene
    property :symbol do
      custom_lookup(self)  # Instead of using translate
    end
  end
  property :symbol do
    custom_lookup(self)  # Instead of using translate
  end
end
```

## Known issues

- The property dispatch type system is complex and has many edge cases,
  especially for `:multiple` and `:both`.
- Identifier translation can fail silently if files are missing or
  malformed.
- The `format` annotation is sometimes inconsistent — some code expects a
  String, other code expects a Symbol.
- Entity properties are not thread-safe by default. Caching in properties
  must be explicit via `persist`.

## See also

- [Architecture](Architecture.md)
- [Design Principles](DesignPrinciples.md)
- [Research: Entity/Association/KB Analysis](../../research/entity-association-kb-analysis.md)
- [scout-essentials: Annotation System](https://github.com/mikisvaz/scout-essentials/blob/main/doc/developer/AnnotationSystem.md)
