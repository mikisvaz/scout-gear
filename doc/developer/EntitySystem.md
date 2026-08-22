# Entity System

This document describes the internal architecture of the Entity system.
It is intended for framework contributors who need to understand how
entity types, formats, properties, and identifier translation work
internally.

## Overview

An Entity is not a new class — it is a plain identifier (usually a String)
annotated in place with a module. `Entity.extended(base)` (entity.rb:9)
gives that module:

- `Annotation` and `Entity::Property` (so `setup`, `property`,
  `persisted?` work on the module itself);
- `Entity::Object` and `AnnotatedArray` (included into instances);
- `@properties = {}` and `@persisted_methods = {}` as class-level state;
- a default `format = base.to_s` (the module's own name).

The annotation mechanism itself (how a module is attached to a String
without changing its class) is implemented in scout-essentials
(`Annotation`); scout-gear builds the entity layer on top of it.

## Entity definition

```ruby
module Research
  module Gene
    extend Entity

    property :tok do "tok:#{self}" end
  end
end

gene = Gene.setup("ENSG1")   # => "ENSG1" annotated with Research::Gene
gene.tok                     # => "tok:ENSG1"
```

`Gene.setup` comes from `Annotation`. `entity_opts` is a legacy alias for
the annotation options hash; `format` is the only option this layer adds
semantics to.

## Property dispatch

`property` (property.rb:42) takes either a name or a `{name => type}` pair.
Types are `:single`, `:single2array`, `:array`, `:array2single`,
`:multiple`, `:both` (the default is `:both`, property.rb:40); anything
else raises `Type of property unknown`.

The block is installed as a *real* method:

- `:single` / `:single2array` → `_single_<name>`
- `:array` / `:array2single` → `_ary_<name>`
- `:multiple` → `_multi_<name>`
- `:both` → `<name>` itself

For every type other than `:both`, a public wrapper `<name>` is then
defined that re-dispatches depending on whether `self` is an Array:

| Type | Array receiver | String receiver |
|------|----------------|-----------------|
| `:single` | collect per element | call block directly |
| `:array` | call block once on the array | `make_array`, take `[0]` |
| `:multiple` | call block once on the array | `make_array`, take `[0]` |

Note the asymmetry verified by probe P034: for `:both` an Array receiver
calls the block **once with the whole array** (so `"tok:#{self}"` yields
`tok:["ENSG1","ENSG2"]`), while an `:array` property called on a single
String is dispatched through `make_array` — the block therefore always
sees an Array. `:multiple` additionally pre-computes results per item and
supports partial persistence (see below).

Properties are registered as `properties[name] = block.parameters`
(property.rb:61) — the *arity signature*, not the block — which is what
`Annotation.tsv` uses to reconstruct column headers.

## Persistence of properties

```ruby
module Research
  module Gene
    extend Entity
    property :tok do "tok:#{self}" end
    persist :tok
  end
end
```

`persist(name, type = :marshal, options = {})` (property.rb:149) records
`persisted_methods[name] = [type, options]` with defaults
`persist: true, dir: Entity.entity_property_cache[self.to_s][name.to_s]`,
where `Entity.entity_property_cache` is `Path.setup('var/entity_property')`
(property.rb:10).

When a persisted property runs, `Entity::Property.persist(name, obj, type,
options)` (property.rb:22) either:

- uses `Persist.annotation_repo_persist(repo, name:id, &block)` when the
  type is `:annotation`/`:annotations` **and** `options[:annotation_repo]`
  is set; or
- otherwise `Persist.persist([name, obj.id] * ":", type, options, &block)`.

Without `persist` (the default `persist: false`) the block simply runs
every time.

For `:multiple` properties the per-item `MultipleEntityProperty`
exception is used as a marker: items whose cache is empty are collected,
annotated, and recomputed in one batch, then stored per item
(property.rb:67-97). `responses.values_at(*self)` preserves the receiver's
order.

## Formats and identifier translation

`format=` (format.rb:2) registers a module in `Entity.formats`, a
`FormatIndex` (a Hash subclass) that looks up formats by exact name or by
`(format)`-style decorations (format.rb:8-45).

`Entity::Identified` (identifiers.rb:13) is the mixin that gives an entity
type identifier files and translation:

- `add_identifiers(file, default = nil, name = nil, description = nil)`
  (identifiers.rb:81) includes the mixin, records `format =` for every
  column of the file (or of every file matched by the `NAMESPACE` glob),
  and appends the file to `identifier_files`.
- `identifier_files` (identifiers.rb:48) resolves the `NAMESPACE` tag
  against the receiver's `namespace` annotation and **rejects** files that
  still contain an unresolved tag.
- `identifier_index(target, source)` (identifiers.rb:63) memoizes
  `TSV.translation_index(identifier_files, source, format, persist: true)`
  in `Persist.memory`, retrying once without a source format if the
  translation fails.

The `to` property (identifiers.rb:26) is defined `:both` and returns
translated identifiers, annotated with the target format; `to(:name)` /
`to(:default)` use the formats recorded by `add_identifiers`. `name` and
`default` are thin wrappers over `to`.

```ruby
Gene.add_identifiers "var/Research/identifiers/Ensembl Gene ID%toAssociated Gene Name",
                     "Ensembl Gene ID", "Associated Gene Name"

g = Gene.setup("ENSG1")
g.to("Associated Gene Name")   # => "GENE1" (annotated, format set)
g.name                         # => "GENE1"
```

Identifier files themselves are TSV files that map one format to another;
`TSV.translation_index` builds the index, so the identifier-file machinery
lives on the TSV layer (see [Processing Tabular
Data](../user/ProcessingTabularData.md)).

## Entity in workflows and the KnowledgeBase

`Entity.prepare_entity(entity, field, options)` (entity.rb:19) is the
bridge used by the workflow layer: given a `field` that is either an
entity module or a registered format name, it annotates the entity and
sets its `format`. It is idempotent for already-annotated values only up
to format reassignment — it duplicates/re-annotates by design.

The KnowledgeBase uses entity modules to interpret association field
specifications (e.g. `:p1`, the entity type given as the database
`source`/`target`): see [Managing Relationships](../user/ManagingRelationships.md).

`EntityWorkflow` (workflow/entity.rb:4) **does** exist in scout-gear. A
module that extends it gets both `Workflow` and `Entity` plus:

- `entity_name=` — sets the name exposed by the `entity` helper;
- `annotation_input(name, ...)` — registers an annotation plus its input
  spec (type, description, default, options) in `@annotation_inputs`
  (entity.rb:22-26); `property_task` then declares it as a workflow input;
- helpers `entity` / `entity_list` that setup the entity from the job's
  inputs (entity.rb:33-40);
- `property_task(task_name, property_type = :single, *args, &block)`
  (entity.rb:48) — the core bridge, detailed below;
- convenience wrappers `entity_task` (`:single`), `list_task` (`:array`),
  `multiple_task` (`:multiple`) (entity.rb:101-110), and the
  `*_alias` variants (`property_task_alias`, `entity_task_alias`,
  `list_task_alias`, `multiple_task_alias`) which additionally route the
  task through `task_alias`.

`property_task` declares, for every annotation of the entity (from
`self.annotations`, using `@annotation_inputs` where present), an input
plus — depending on `property_type` — either a single `entity_name`
string input with `jobname: true` (`:single`, `:single2array`), a `:list`
array input (`:array`, `:array2single`, `:multiple`), or both (`:both`)
(entity.rb:52-70). It then defines **two** properties: `<name>_job`
(dispatched as `property_type`), which returns the Step from
`job(task_name, ...)`; and `<name>`, which joins a running job, cleans
recoverable errors (re-raising non-recoverable ones via
`job.exception`), runs the job unless done, and returns `job.load` —
casting each element of an Array result with `.run` (entity.rb:71-99).
The property name is `task_name` with any `entity_name`/`entity_name_list`/
`list` prefix stripped (entity.rb:70-71).

```ruby
module Research
  extend Workflow
  extend EntityWorkflow
  self.entity_name = :gene
  annotation_input :cohort, :string, "Cohort name"

  property_task :mean_expression, :single do
    gene = Gene.setup(inputs[:gene])
    gene.mean_expression(cohort: inputs[:cohort])
  end
end

Research::Gene.setup("ENSG1").mean_expression_job  # => Step (not run)
Research::Gene.setup("ENSG1").mean_expression      # runs and loads
```

## Extension points

- `Entity.formats` — the format→module registry; `Entity.prepare_entity`
  uses `find` (suffix-insensitive, `(format)`-aware).
- `Entity::Identified` — include via `add_identifiers` to get `to`, `name`,
  `default`, `identifier_files`, `identifier_index`.
- `Entity::Property.persist` / `persisted_methods` — the persistence hook
  used by `Entity.persist` and the annotation-repo path.
- `Entity.entity_property_cache` — `Path.setup('var/entity_property')`,
  overridable.

## See also

- [Working With Entities](../user/WorkingWithEntities.md)
- [Managing Relationships](../user/ManagingRelationships.md) — how entity types resolve KB fields.
- [Persistence Engines](PersistenceEngines.md) — `annotation_repo_persist`.
