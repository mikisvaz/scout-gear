# Managing Relationships

This document explains how to represent and query relationships between
entities using the Association and KnowledgeBase subsystems.

It covers: registering associations, declaring source/target entity types
and formats, building persisted indexes, and querying related entities.

## Overview

### Association

An association is a TSV file (or TSV object, or block that produces one)
that links two entity types. Registering it builds a lookup index — a
two-way TSV (`type: :double`) whose key is `source~target` pairs.

### KnowledgeBase

A KnowledgeBase is a registry of associations under a directory. Register
associations by name, then query them.

```ruby
kb = KnowledgeBase.new("var/MyStudy")   # dir for kb + entity/identifiers
kb.register :geneprotein, "gene_protein.tsv",
            source: "Ensembl Gene ID=~Gene", target: "Ensembl Protein ID=~Protein"
```

`KnowledgeBase.new(dir)` stores its state under `dir` (knowledge_base.rb:16);
`kb.register(name, file=nil, options={}, &block)` accepts a file path, a
TSV, or a block returning a TSV (registry.rb:5).

### Field specifications

Source/target use the syntax `"Format name=~Entity type"`:

- `"Ensembl Gene ID=~Gene"` — Ensembl-format Gene entities.
- `"Uniprot Accession=~Protein"` — Uniprot-format Protein entities.

The format part is used for identifier translation; the entity-type part
(what follows `=~`) selects the Entity module used to annotate results
(association/fields.rb). Entity types must be registered for the KB
namespace via the Entity registry (see
[Working with Entities](WorkingWithEntities.md)) before they can be used
in field specifications.

The keyword form without `=~` — `"Field name (Format)"` — and the plain
`source:`/`target:` option form (`source: '=>Initials'`) are legacy rbbt
syntax; scout-gear's own field parser handles the `=~` form. Downstream
workflows (e.g. AGS) still written against rbbt use the legacy forms.

### Traverser

The Traverser (`kb.traverse`) is the query engine that follows
associations. It understands a rule language of the form
`SOURCE DATABASE TARGET`, e.g.:

```ruby
kb.traverse ["Clei~Guille brothers Isa~Miki"]
```

Rule element forms (traverse.rb:13-28, 60-66):

- literal entity `"Clei~Guille"` — a single `source~target` key;
- `?name` — wildcard, bound by earlier rules and carried forward;
- `:name` — named list, resolved with `kb.load_list(name)`;
- `DATABASE@kb` / wildcards in the database name — select across
  registered databases (traverse.rb:166-186);
- trailing `- conditions` — AssociationItem field conditions
  (traverse.rb:197-200).

`kb.traverse(rules, true)` skips path reconstruction
(traverse.rb:280-285).

The Traverser is exercised by scout-gear's own tests
(test/scout/knowledge_base/test_traverse.rb) but is **not used by any of
the four audited downstream workflows**; treat it as an advanced
engine-level API.

## Defining associations

### Registering an association

```ruby
kb.register :name, "data.tsv", **options
```

| Option | Purpose |
|--------|---------|
| `:source` / `:target` | Field specification (see above) |
| `:fields` | Additional fields to include in the index |
| `:undirected` | Treat the association as undirected |
| `:persist` | Persist the index (engine, e.g. `true`, `:HDB`) |

`:persist` delegates to the Persist engine list; see
[Persistence Engines](../developer/PersistenceEngines.md).

### What registration builds

`kb.register` normalises the source data through `Association.index`
(association/index.rb), producing a `type: :double` TSV keyed by
`source~target` strings, with the key field split into
`source_entity`/`target_entity` fields for query convenience
(`kb.get_index(name)` returns this TSV; registry.rb:71).

## Querying relationships

### Direct lookups

```ruby
# children/parents for a node (query.rb)
kb.children(:geneprotein, "ENSG00000141510")  # source -> target
kb.parents(:geneprotein, "ENSP00001")         # target -> source
kb.neighbours(:geneprotein, "ENSG00000141510") # => {parents: [...], children: [...]}

# subset: all matches for a node or set of nodes; returns an AnnotatedArray
# of AssociationItem (query.rb:15)
kb.subset(:geneprotein, "ENSG00000141510")

# count is NOT a KB method; use subset(...).length or traverse matches
```

`kb.source(name)` / `kb.target(name)` return the *field names* of the
index (`pair(name)[0]/[1]` from `get_index(name).key_field.split("~")`,
registry.rb:53-60) — not entity lists.

### Using Entity properties

Association results are annotated with the entity types declared in the
field specifications, so entity properties apply:

```ruby
module Research
  module Gene
    extend Entity
    property :proteins do
      kb = KnowledgeBase.new("var/Research/knowledge_base")
      kb.children(:geneprotein, self).target_entity
    end
  end
end

gene = Research::Gene.setup("ENSG00000141510")
gene.proteins  # => annotated Protein entities
```

`KnowledgeBase.get_kb` does **not exist** in scout-gear; construct the kb
with `KnowledgeBase.new(dir)` where you need it (knowledge_base.rb:16).

### Using the index directly

```ruby
index = kb.get_index(:geneprotein)   # TSV, type: :double
index.keys.sample                    # => "ENSG00000141510~ENSP00001"
index["ENSG00000141510~ENSP00001"]   # => {"source_entity" => [...], "target_entity" => [...]}
```

## AssociationItem

`kb.subset` / `kb.children` / `kb.parents` return AssociationItems — the
`source~target` string annotated with `knowledge_base`, `database` and
`reverse` (association/item.rb:4-8). Useful properties:

- `source_entity` / `target_entity` — annotated entities at each end
  (array2single);
- `info` / `name` / `full_name`;
- `invert` — swap ends and flip `reverse` (:both, item.rb:20-35);
- `part` — `[[source, target], ...]` partitions (:array2single).

## Persistence

Association indexes can be persisted for fast reloading:

```ruby
kb.register :geneprotein, "data.tsv", persist: true
```

This builds a database index on first load and reuses it on subsequent
loads. See [Caching Data](CachingData.md) for persistence engines.

## Common mistakes

- **Wrong field specification format**: the `=~` syntax must separate the
  identifier format from the entity type. The legacy `field (Format)`
  syntax belongs to rbbt KnowledgeBase; scout-gear parses `=~`.
- **Not persisting large associations**: building an index over a large
  association file is expensive; use `persist:` to avoid rebuilding.
- **Confusing source and target direction**: `children` follow
  source→target, `parents` the reverse. `kb.source`/`kb.target` return
  field *names*, not entities.
- **Expecting `kb.find`/`kb.count`**: these are not scout-gear KnowledgeBase
  methods. Use `subset`/`children`/`parents`/`neighbours`, or the
  Traverser.
- **Expecting KnowledgeBase to be thread-safe**: indexes are built once and
  shared; concurrent writes are not part of the design. Build indexes in
  advance or serialize writes.
- **Not registering all associations before traversing**: the Traverser
  needs every database named in its rules to be registered first.

## See also

- [Working with Entities](WorkingWithEntities.md) — entity modules and
  annotation of results.
- [Processing Tabular Data](ProcessingTabularData.md) — the TSV layer
  underneath association files.
- [Caching Data](CachingData.md) — persistence usage.
- [Persistence Engines](../developer/PersistenceEngines.md) — engine list.
- [Cookbook](Cookbook.md)
