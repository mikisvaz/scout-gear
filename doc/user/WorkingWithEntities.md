# Working with Entities

This document explains how to attach types and properties to identifiers
using the Entity system. It covers defining entity types, adding properties,
and translating between identifier formats.

It is intended for workflow authors and data analysts who work with typed
identifiers (gene IDs, protein IDs, compound IDs, etc.).

## What problem does this solve?

In data analysis, identifiers represent real-world entities — genes,
proteins, drugs, patients. A raw string like `"ENSG00000141510"` is just a
string; you can't ask it for its gene name, its protein products, or its
position in the genome.

The Entity system lets you attach a type to any identifier and define
properties that are computed or looked up on demand. This turns raw
identifiers into rich objects with domain-specific behaviors.

Entities integrate with the workflow system (results can be annotated as
entities), the TSV system (data can be loaded for entity properties), and
the KnowledgeBase (entities can be queried for relationships).

## When do I use it?

- When you work with typed identifiers (gene IDs, protein IDs, etc.).
- When you need to translate between identifier formats (Ensembl to Gene
  Symbol).
- When you want to attach computed properties to identifiers (e.g.,
  `gene.protein` returns all proteins associated with that gene).
- When you want to use the KnowledgeBase to query relationships between
  entities.

## Core concepts

### Entity

An Entity is a type attached to a plain object (usually a String). You
don't create new classes; you annotate existing strings:

```ruby
module Research
  module Gene
    extend Entity

    property :protein_ids do
      ["ENSP00001", "ENSP00002"]
    end
  end
end
```

To use the entity:

```ruby
gene = Research::Gene.setup("ENSG00000141510")
gene.protein_ids  # => ["ENSP00001", "ENSP00002"]
```

The `setup` call annotates the string in place — it doesn't create a new
object. The same string now has all the `Gene` properties.

### Properties

Properties are methods defined on an Entity module that can be called on
any instance of that entity type. The property block executes in the
context of the string, so `self` is the identifier.

```ruby
module Research
  module Gene
    extend Entity

    property :length do
      self.length  # self is the string "ENSG00000141510"
    end

    property :annotation, :pos do |pos|
      # Property with arguments
      "#{self}:#{pos}"
    end
  end
end
```

Properties support different dispatch types, documented in the developer
docs on the [Entity System](../developer/EntitySystem.md). The most common
are `:array` (call the block on each element when self is an array) and
`:single` (always call the block on the whole self).

### Format and identifier translation

Entities carry a `format` — the identifier format they use. This lets you
translate between formats automatically:

```ruby
gene = Research::Gene.setup("ENSG00000141510", format: "Ensembl Gene ID")
gene.format  # => "Ensembl Gene ID"
```

Identifier translation uses TSV files that map one format to another. These
files follow a convention:
```
var/<namespace>/identifiers/<source_format>%to<target_format>
```

## Defining an entity type

### Basic definition

```ruby
module Research
  module Sample
    extend Entity

    property :patient_id do
      self.split("-")[0..2] * "-"
    end
  end
end

sample = Research::Sample.setup("SAMPLE-001-TUMOR")
sample.patient_id  # => "SAMPLE-001"
```

### Property with TSV data

```ruby
module Research
  module Gene
    extend Entity

    property :expression do
      tsv = TSV.open("expression_data.tsv")
      tsv[self]
    end
  end
end

gene = Research::Gene.setup("ENSG00000141510")
gene.expression  # => the row from the TSV
```

## Translating identifiers

Entity properties can translate identifiers between formats using
identifier files:

```ruby
module Research
  module Gene
    extend Entity

    property :symbol do
      translate "Ensembl Gene ID", "Associated Gene Name"
    end
  end
end
```

The `translate` method looks up translation files at the conventional
path. If you need to add custom identifier files:

```ruby
Research::Gene.identifier_files << "path/to/identifiers.tsv"
```

## Entities in workflows

Entities integrate with workflows through the `EntityWorkflow` mixin. When
a workflow extends `EntityWorkflow`, entity properties become available as
workflow helpers, making them accessible inside task bodies.

## Entities in the KnowledgeBase

Entities can be queried for relationships through the KnowledgeBase. The
KnowledgeBase uses the entity system to resolve properties and traverse
relationships between entity types.

See [Managing Relationships](ManagingRelationships.md) for details.

## Common mistakes

- **Forgetting to set a namespace**: Entities need a namespace (the module
  they're defined in) to find identifier files and data. Always define
  entities inside a module.
- **Expecting `setup` to create a new object**: `setup` annotates the
  existing string in place. The return value is the same object, now with
  entity methods.
- **Using `self` incorrectly in property blocks**: `self` is the identifier
  string, not a class instance. For properties that need to call other
  properties, define them and call `self.other_property`.
- **Not providing identifier files**: If `translate` can't find a
  translation file, it raises an error. Make sure identifier files exist
  at the expected path.
- **Expecting properties to be cached by default**: Properties are
  recomputed every call unless you use persistence inside the property
  block (e.g., `Persist.persist`).

## See also

- [scout-essentials: Annotating Data](https://github.com/mikisvaz/scout-essentials/blob/main/doc/user/AnnotatingData.md)
- [Processing Tabular Data](ProcessingTabularData.md)
- [Managing Relationships](ManagingRelationships.md)
- [Cookbook](Cookbook.md)
