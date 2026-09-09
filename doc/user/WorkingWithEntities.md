# Working with Entities

This document explains how to attach types and properties to identifiers
using the Entity system: defining entity types, adding properties,
translating between identifier formats, and using entities from
workflows.

It is intended for workflow authors and data analysts who work with typed
identifiers (gene IDs, protein IDs, compound IDs, etc.).

## What problem does this solve?

In data analysis, identifiers represent real-world entities — genes,
proteins, drugs, patients. A raw string like `"ENSG00000141510"` is just a
string; you cannot ask it for its gene name, its protein products, or its
position in the genome.

The Entity system lets you attach a type to any identifier and define
properties that are computed or looked up on demand. Entities integrate
with the workflow system (results can be annotated as entities), the TSV
system (data can be loaded for entity properties), and the KnowledgeBase
(entities can be queried for relationships).

## Core concepts

### Entity

An Entity is a module *extended onto* an existing object (usually a
String). You do not create new classes:

```ruby
module Research
  module Gene
    extend Entity

    property :protein_ids do
      ["ENSP00001", "ENSP00002"]
    end
  end
end

gene = Research::Gene.setup("ENSG00000141510")
gene.protein_ids  # => ["ENSP00001", "ENSP00002"]
```

`Gene.setup` is `Annotation.setup`: it records the module on the object
and returns **the same object**. The String keeps its class; entity
methods are dispatched through the annotation layer.

Setting up a second entity module on the same object **stacks** it: both
modules annotate the object, `annotation_types` lists both, and
`all_properties` (the properties of every annotating module) is their
union. `base_entity` is the module added last.

`Entity.prepare_entity(value, field, options)` is the sibling entry point
used by the TSV and KnowledgeBase layers: it returns the value unchanged
unless it is a String, an Array or a Numeric, always duplicates those
three first, and annotates the copy with the module given by `field` (an
entity module or a registered format name).

### Properties

A property is defined on the entity module with `property`; its block runs
with `self` bound to the identifier, and may take arguments:

```ruby
property :tok do "tok:#{self}" end           # self is the identifier

property :at_pos => :both do |pos|           # property with arguments
  "#{self}:#{pos}"
end
```

The dispatch types (`:single`, `:single2array`, `:array`, `:array2single`,
`:multiple`, `:both`) control how the block is invoked when the receiver
is a *collection* of entities; see the [Entity
System](../developer/EntitySystem.md) for the full matrix. `:single2array`
and `:array2single` are accepted names that behave exactly like `:single`
and `:array`. Two behaviors worth knowing up front:

- an `:array` property's block **always** sees an Array — calling it on a
  single String wraps the String in a one-element array first;
- the default type is `:both`, and on an Array receiver the block is
  called once with the whole array (not once per element).

### Format and identifier translation

An entity can carry a `format` — the identifier format it is currently in
(e.g. `"Ensembl Gene ID"`). When an entity type declares identifier files
(see below), you can translate to other registered formats:

```ruby
gene = Gene.setup("ENSG1", format: "Ensembl Gene ID")
gene.to("Associated Gene Name")   # => "GENE1", annotated with the target format
gene.name                         # => "GENE1" (the name format, if registered)
```

Identifier files are ordinary TSV files whose **header field names are
the identifier formats** they map between — for instance a file with the
header `#Name,Alias,ID` maps between all three formats, in either
direction, and new format pairs become available by adding columns. The
source and target formats are chosen at translation time from the file's
columns; there is no per-pair naming convention. Files are declared
explicitly per entity type (see below).

## Defining an entity type

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
sample.patient_id  # => "SAMPLE-001-TUMOR"
```

(The example above is literal: `self.split("-")[0..2] * "-"` on
`"SAMPLE-001-TUMOR"` returns the same string.)

To make an entity type translatable, declare its identifier files:

```ruby
module Research
  module Gene
    extend Entity
    # Entity::Identified is included automatically by add_identifiers
    # (or explicitly: `include Entity::Identified`).

    add_identifiers "var/Research/identifiers",
                    "Ensembl Gene ID", "Associated Gene Name"
  end
end

# The identifier file is a plain TSV whose header names are the formats:
#   #Ensembl Gene ID,Associated Gene Name,Entrez Gene ID
#   ENSG00000141510,GENE1,7157
```

`add_identifiers` registers every field of the file as a known format,
records the default/name formats, and appends the file to
`identifier_files`. A path containing the literal tag `NAMESPACE` is
expanded per entity using the entity's `namespace` annotation; files whose
tag cannot be resolved are rejected (with a warning) rather than used.

When more than one declared file can translate a source into the target,
the **first** usable file wins and the others are not consulted; if no
single file covers the pair, a chained translation through an
intermediate format is tried before failing. A direct file covering the
pair wins even when a longer chain is declared first, and a missing
middle link (no file for either hop) raises `Errno::ENOENT` when it tries
to produce the absent intermediate, rather than silently passing the
value through.

Note also that format registration is global and **first-write-wins**: if
two entity types register the same format string, the second one is
silently ignored.

Extra files can be appended afterwards:

```ruby
Research::Gene.identifier_files << "path/to/identifiers.tsv"
```

### Properties with TSV data

```ruby
property :expression do
  TSV.open("expression_data.tsv")[self]
end
```

Opening a TSV inside a property block re-reads it on every call. Use
persistence to avoid that:

```ruby
property :expression do
  Persist.memory("expression-for-gene") { TSV.open("expression_data.tsv")[self] }
end
```

or declare the property persisted. The class-level `persist(name, type,
options)` (property.rb:149) registers the property in
`@persisted_methods` with default `dir:
Entity.entity_property_cache[self.to_s][name.to_s]` — i.e.
`var/entity_property/<EntityModule>/<property>` (property.rb:4-8,
150-153):

```ruby
property :expression do
  TSV.open("expression_data.tsv")[self]
end
persist :expression, :marshal
```

`persisted?(name)` tests registration and `unpersist(name)` removes it
(property.rb:156-164). Two caveats worth knowing:

- the cache file is keyed by the entity's `id` — the digest of its value
  *plus its annotations* — so the same identifier with a different
  `format` or `namespace` is a separate cache entry, not a stale one;
- there is no recompute on age: without a `:check` file the persisted
  value is served as-is, `unpersist` only removes the registration
  (the file stays on disk and is read back if the property is
  re-persisted), and one file is written per argument set.

See [Caching Data](CachingData.md) for the persistence API.

## Entities in workflows

The bridge is the `EntityWorkflow` mixin (workflow/entity.rb). A module
that extends it gets both `Workflow` and `Entity`, plus:

- an `entity` helper (and `entity_name=` to rename it) that set-ups the
  entity from the job inputs;
- `annotation_input(name, ...)` to declare annotations as workflow inputs;
- a `job` property to launch tasks on an entity or a list;
- `property_task` / `entity_task` / `list_task` / `multiple_task` (+
  `*_alias` variants), which define a task *and* a same-named entity
  property that runs the job, joins it, handles recoverable errors, and
  loads the result.

```ruby
module Research
  module Gene
    extend EntityWorkflow
    property_task :tok do "tok:#{entity}" end
  end
end

Research::Gene.setup("ENSG1").tok        # runs the task
Research::Gene.setup("ENSG1").tok_job   # the underlying Step
```

## Entities in the KnowledgeBase

The KnowledgeBase uses entity modules to interpret association field
specifications and to set up association items; entity types also
provide the identifier files used for cross-format joins. `kb.register`
with `source: "Field=~Type"` annotates the entity *type* on query
results; the annotation *values* (`entity_options` such as `language:
'es'`) come from `kb.entity_options` / per-database registration
options, not from the field specification. `KnowledgeBase`-specific
helper `kb.define_entity_modules` creates the `Object::<Type>` module
for every `entity_options` entry that lists `:identifiers` and
registers every identifier header format into `Entity.formats`; the
type keys it uses must be bare constant names (`"Kin"`, not
`"Object::Kin"`). See
[Managing Relationships](ManagingRelationships.md).

## Common mistakes

- **Expecting `setup` to create a new object**: `setup` annotates the
  existing object and returns it. `gene.object_id ==
  "ENSG1".object_id` may hold after setup on a fresh string.
- **Expecting an `:array` property to receive a String**: the block always
  sees an Array; handle single values with the `:single`/`:both` types.
- **Calling the default (`:both`) dispatch on a list**: the block runs
  once with the whole array, so `"tok:#{self}"` yields the array's
  `to_s`, not per-element tokens.
- **Translating without declaring identifier files**: `to` raises if no
  translation index can be built from `identifier_files`. Declare them
  with `add_identifiers`.
- **Expecting properties to be cached by default**: they are recomputed on
  every call unless the property is declared via the class-level
  `persist(name, type)` or the block uses `Persist.memory`/`Persist.persist`
  directly.
- **Using `NAMESPACE` paths without a namespace**: unresolved
  `NAMESPACE` tags cause the file to be dropped (warn), not to fail.
- **Re-using one array with two entity types**: `setup` annotates in
  place, and the per-container array-property cache is keyed only by the
  property name and arguments — a second entity type annotating the same
  array will find the first type's cached results for a same-named
  property.
- **Expecting `annotated_array: false` to keep an array plain**:
  annotated arrays always get `AnnotatedArray` extended; the option has
  no effect.

## See also

- [Entity System](../developer/EntitySystem.md) — internal architecture,
  dispatch table, persistence of properties.
- [Processing Tabular Data](ProcessingTabularData.md) — the TSV layer
  underneath identifier files.
- [Managing Relationships](ManagingRelationships.md) — KnowledgeBase.
