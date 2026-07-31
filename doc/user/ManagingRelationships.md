# Managing Relationships

This document explains how to represent and query relationships between
entities using the Association and KnowledgeBase systems.

It is intended for workflow authors and data analysts who need to model and
query complex relationships between entities (e.g., gene-protein
interactions, drug-target associations, pathway memberships).

## What problem does this solve?

When analyzing data, you often need to answer questions like:

- What proteins are produced by this gene?
- Which drugs target this protein?
- What pathways is this gene part of?
- List all genes that interact with this set of genes.

These are relationship queries over a graph of entities. Without a
framework, you'd write custom code for each relationship type, manage
indexes manually, and reimplement traversal logic.

The KnowledgeBase system lets you:

- Register relationship datasets (associations) by name.
- Query relationships by source, target, or both.
- Traverse the graph (find all entities reachable from a starting point).
- Use the same query API regardless of the underlying data format.

## When do I use it?

- When you have multiple relationship datasets (interaction files, pathway
  files, etc.) and need a unified query API.
- When you need to traverse relationships (find all genes connected to a
  given drug through any path).
- When you want to attach relationship data to Entity properties (e.g.,
  `gene.interactions`).
- When you want to build reports or summaries across multiple relationship
  types.

## Core concepts

### Association

An Association is a dataset describing relationships between two entity
types. It's defined by:

- A **source** entity type and field
- A **target** entity type and field
- Additional **fields** (e.g., interaction type, score)

An association is typically loaded from a TSV file where the source and
target identifiers are in specific columns.

### KnowledgeBase

A KnowledgeBase is a registry of associations. You register associations
by name, and then query them using a consistent API.

```ruby
kb = KnowledgeBase.new("MyStudy")
kb.register :geneprotein, "gene_protein.tsv",
            :source => "Ensembl Gene ID=~Gene", :target => "Ensembl Protein ID=~Protein"

kb.register :pathway, "pathway_membership.tsv",
            :source => "Pathway ID=~Pathway", :target => "Ensembl Gene ID=~Gene"
```

### Traverser

The Traverser is the query engine for the KnowledgeBase. It lets you find
related entities by following associations.

```ruby
# Find all proteins for a gene
kb.traverser(:geneprotein, "ENSG00000141510", :p)
```

The traverser knows about the direction (source to target or target to
source) and can combine multiple associations into paths.

## Defining associations

### Registering an association

```ruby
kb.register :name, "data.tsv", **options
```

Options:

| Option | Purpose |
|--------|---------|
| `:source` | Source field specification (see below) |
| `:target` | Target field specification (see below) |
| `:fields` | Additional fields to include |
| `:namespace` | Namespace for identifier translation |
| `:persist` | Persist the index for reuse |

### Field specifications

Source and target are specified using the syntax:
```
"Format name=~Entity type"
```

For example:
- `"Ensembl Gene ID=~Gene"` — The field uses Ensembl Gene ID format and
  maps to the `Gene` entity.
- `"Uniprot Accession=~Protein"` — Uniprot format, `Protein` entity.

This tells the KnowledgeBase which entity type each column represents and
what identifier format it uses, enabling identifier translation and entity
property integration.

## Querying relationships

### Find related entities

```ruby
# Source to Target
kb.find(:geneprotein, "ENSG00000141510", :p)

# Target to Source
kb.find(:geneprotein, :p, "ENSP00001")

# All relationships for a set of entities
kb.find(:geneprotein, ["ENSG00001", "ENSG00002"], :p)
```

### Using Entity properties

Once associations are registered, you can define entity properties that
query the KnowledgeBase:

```ruby
module Research
  module Gene
    extend Entity
    property :proteins do
      kb = KnowledgeBase.new("Research")
      kb.find(:geneprotein, self, :p)
    end
  end
end

gene = Research::Gene.setup("ENSG00000141510")
gene.proteins  # => list of proteins associated with this gene
```

### Counting and summarizing

```ruby
count = kb.count(:geneprotein, "ENSG00000141510", :p)
```

### Using the index directly

```ruby
index = kb.get_index(:geneprotein)
index["ENSG00000141510"]  # => all rows for this gene
```

## Traversing the graph

The Traverser can follow multiple associations to find indirectly related
entities:

```ruby
# Find all drugs that target proteins of this gene
path = kb.subset(:geneprotein, :drugtarget)
result = kb.traverse(path, "ENSG00000141510")
```

The traverse path is a sequence of association names. The Traverser
follows each association in order, collecting entities at each step.

## Persistence

Association indexes can be persisted for fast reloading:

```ruby
kb.register :geneprotein, "data.tsv", persist: true
```

This builds a database index on first load and reuses it on subsequent
loads. See [Caching Data](CachingData.md) for details on persistence
engines.

## Common mistakes

- **Wrong field specification format**: The `=~` syntax must separate the
  identifier format from the entity type. Check that formats match your
  data.
- **Not persisting large associations**: Building an index for a large
  association file is expensive. Use `persist: true` to avoid rebuilding.
- **Confusing source and target direction**: `find(name, source, target)`
  expects specific directions. If you get empty results, try swapping the
  arguments or using `:p` (positive direction) vs `:n` (negative direction).
- **Expecting KnowledgeBase to be thread-safe**: The KnowledgeBase and its
  indexes are not designed for concurrent writes. Use them from a single
  thread, or build indexes in advance and share read-only.
- **Not registering all associations before traversing**: The Traverser
  needs all associations in its path to be registered. Register everything
  you need before querying.

## See also

- [Working with Entities](WorkingWithEntities.md)
- [Processing Tabular Data](ProcessingTabularData.md)
- [Caching Data](CachingData.md)
- [Cookbook](Cookbook.md)
