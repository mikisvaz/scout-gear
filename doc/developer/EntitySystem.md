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
`:multiple`, `:both` (the default is `:both`, property.rb:41); anything
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

`:single2array` and `:array2single` are accepted as distinct types but
install the same real method and produce the same wrapper dispatch as
`:single` and `:array` respectively (property.rb:50-56).

Note the asymmetry verified by probe P034: for `:both` an Array receiver
calls the block **once with the whole array** (so `"tok:#{self}"` yields
`tok:["ENSG1","ENSG2"]`), while an `:array` property called on a single
String is dispatched through `make_array` — the block therefore always
sees an Array. `:multiple` additionally pre-computes results per item and
supports partial persistence (see below).

Properties are registered as `properties[name] = block.parameters`
(property.rb:63) — the *arity signature*, not the block — which is what
`Annotation.tsv` uses to reconstruct column headers. Only non-`:both`
types get a generated public wrapper `<name>` delegating to
`_single_`/`_ary_`/`_multi_`; for `:both` the block *is* the public
method.

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

Two consequences of that container cache are worth stating:

- a contained element served from an earlier container run does **not**
  re-run the block — the per-item result is read from the container's
  `_ary_property_cache` via `container_index` — while an *uncontained*
  single entity (created by `setup`, not by indexing an array) runs the
  block on every call;
- the cache key is `Misc.digest({:name => name, :args => args})`
  (property.rb:137), which omits the entity module, and `Entity.setup`
  annotates an array in place; a second entity module annotating the
  *same* array therefore finds the first module's entry for a
  same-named property. Do not annotate one array with two entity
  modules and expect per-module cache separation. The fill itself
  (`||=`) is not atomic: under concurrent cold access the block can run
  twice and losing readers get equal values in distinct objects.

## What `persist` actually caches

The `:dir` default is captured when `persist` is declared, from
`Entity.entity_property_cache`, so reassigning
`Entity.entity_property_cache` afterwards does not move an
already-declared property. The cache file is
`<dir>/<property>:<id digest>:<args digest>` — one file per argument set,
where `obj.id` is the digest of the value plus its annotation info; a
different `format`/`namespace` annotation is therefore a different cache
entry, not an invalidation of the old one.

Recompute happens only when a `:check` file is newer than the cache
file, when `unpersist(name)` removed the registration, or when the
property was never persisted. With no `:check` the file is served
unconditionally — there is no mtime- or age-based recompute.
`unpersist` removes the registration but leaves the cache file on disk,
and re-`persist`-ing the property reads that stale file back; there is
no built-in purge.

## Formats and identifier translation

`format=` (format.rb:2) registers a module in `Entity.formats`, a
`FormatIndex` (a Hash subclass) that looks up formats by exact name or by
`(format)`-style decorations (format.rb:8-45).

Registration is **first-write-wins and silent**: `format=` stores with
`Entity.formats[format] ||= self`, so if two modules claim the same
format string the second registration is ignored and
`Entity.formats["..."]` keeps returning the first module — no error, no
warning, no method of discovering the loser afterwards. A module may of
course register several format names. `find` looks up the exact key
first, then the key `to_s`, then a parenthesized decoration such as
`Associated Gene Name (Hsa)` — a decoration matches only when the
*paren-less* form is itself a registered key, and the parenthesized
string itself is never a key. Reads are cached in `@find_cache`, which
`[]=` clears wholesale before storing; the cache is process-local and
thread-shared. `Entity.formats` and its cache are therefore usable from
several threads on MRI — a stable key cannot be lost by concurrent
churn — but it is not protected against lost-update registrations under
simultaneous first-time writers. The one way a *reader* can lose: a `find`/`include?` that misses a
name just before a concurrent first `[]=` for that name writes a stale
`nil` into the freshly rebuilt cache, so that reader keeps seeing a miss
until the next `[]=` clears it again — register formats before spawning
worker threads.

`Entity::Identified` (identifiers.rb:13) is the mixin that gives an entity
type identifier files and translation:

- `add_identifiers(file, default = nil, name = nil, description = nil)`
  (identifiers.rb:84) includes the mixin, records `format =` for every
  column of the file, and appends the file to `identifier_files`.
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
# The identifier file is a plain TSV; its header field names are the
# formats it registers:
#   #Ensembl Gene ID,Associated Gene Name
Gene.add_identifiers "var/Research/identifiers",
                     "Ensembl Gene ID", "Associated Gene Name"

g = Gene.setup("ENSG1", format: "Ensembl Gene ID")
g.to("Associated Gene Name")   # => "GENE1" (annotated, format set)
g.name                         # => "GENE1"
```

Identifier files are TSVs whose header field names are the identifier
formats; the source/target pair is chosen at translation time from the
file's columns, not when the file is defined. When several registered
identifier files can translate the same source into the same target, the
**first** file in `identifier_files` that yields a usable index wins and
the rest are not consulted; if no file translates directly, a chained
(two-step) translation through an intermediate format is preferred over
failing.
`TSV.translation_index` builds the index, so the identifier-file machinery
lives on the TSV layer (see [Processing Tabular
Data](../user/ProcessingTabularData.md)).

## Entity in workflows and the KnowledgeBase

`Entity.prepare_entity(entity, field, options)` (entity.rb:19) is the
bridge used by the workflow layer and by the TSV layer. Given a `field`
that is either an entity module or a registered format name, it returns
the entity **unchanged** unless it is a String, Array or Numeric; for
those three it always `dup`s first (frozen input included) and then
annotates the copy, so the receiver is never mutated. `options[:format]`
sets the `format` annotation only when the entity module declares one
(that is, for `Entity::Identified` types); passing `format:` for a module
that does not include `Entity::Identified` is silently ignored, and a
`field` that resolves to neither a module nor a registered format
returns the value unannotated. Arrays are extended with
`AnnotatedArray`; `dup_array: true` additionally dups the elements
themselves. Re-preparing an already annotated value stacks the module on
top of the existing ones instead of replacing them.

The KnowledgeBase uses entity modules to interpret association field
specifications (the entity type given as the database `source`/`target`,
resolved through `Entity.formats`; an unregistered type leaves the ends
unannotated rather than raising): see
[Managing Relationships](../user/ManagingRelationships.md).

Two KnowledgeBase-specific integration points:

- `kb.entity_options` maps an entity type name to a Hash of options
  (`:identifiers`, `:organism`, ...); the merged result is carried on the
  built index, so AssociationItems inherit it. The type name must be a
  **bare Ruby constant name** (`"Kin"`, not `"Object::Kin"`):
  `define_entity_modules` resolves the key with `Object.const_get` and
  creates it with `Object.const_set` when missing; the qualified form is
  accepted by `const_get` only while the constant already exists, and
  raises `NameError: wrong constant name` when it has to be *created*.
- `kb.define_entity_modules` (knowledge_base/entity.rb:152) creates the
  `Object::<Entity>` module for every `entity_options` entry that lists
  `:identifiers`, and registers every identifier header format into
  `Entity.formats` (`add_identifiers`), making translation available to
  the whole process.

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
- a `job` property (`property job: :both`, entity.rb:39-45) present on
  **every** `EntityWorkflow` entity: `entity.job(task_name)` returns the
  Step (list form for an `AnnotatedArray` receiver, the entity itself
  otherwise);
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

## The annotated-object surface

Two small files complete the picture and are worth knowing by name:

- `lib/scout/entity/object.rb` defines exactly four instance methods on
  `Entity::Object`: `entity_classes` (the entity modules annotating
  `self`), `base_entity` (`entity_classes.last`, i.e. the module added by
  the most recent `setup`), `_ary_property_cache` (a lazily created Hash
  placed on the annotated *array*, shared by the array-property dispatch
  cache; two caveats: the fill `...[cache_code] ||= ...` is not atomic,
  so a side-effecting array-property block can run twice under
  concurrent cold access, and the key
  `Misc.digest({:name => name, :args => args})` omits the entity module,
  so annotating the *same* array with a second entity module lets a
  same-named property be served from the first module's batch), and
  `all_properties` — the union of the `properties` of every
  annotating entity class, so stacked modules accumulate rather than
  mask each other. There is no `load` method and no `Entity::LoadError`;
  persisted property values come back through the ordinary `Persist`
  serialization of `persist`.
- `lib/scout/entity/named_array.rb` redefines `NamedArray#[]`: after the
  position is resolved, the value is passed through
  `Entity.prepare_entity` with the **field name** as the format key. This
  is how a row accessed as `row["Ensembl Gene ID"]` comes back annotated
  with the module registered for that format, while `row[0]` keeps the
  raw value unless the integer is also a valid field name.

The module-level `setup` (from `Annotation`) annotates the given
String/Array **in place** (the same object is returned) and extends an
Array with `AnnotatedArray`. Note that the `annotated_array: false`
option of `Entity.prepare_entity` is ineffective — the guard tests
`! options[:annotated_array] == FalseClass`, which is never true, so the
module is always extended.

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
