# Investigation: Entity System — Probe Findings

> **Non-normative.** This document is a working investigation with
> implementation details, code exploration notes, and hypotheses. Refer
> to `doc/developer/EntitySystem.md` and `doc/user/WorkingWithEntities.md`
> for maintained architectural documentation.

Consolidated record of the twenty-three probes run against the Entity
layer (`lib/scout/entity.rb`, `lib/scout/entity/**`,
`lib/scout/workflow/entity.rb`, scout-gear) during the
documentation-consolidation campaign. Each probe was executed through
`Observation/probe(<name>)` and its receipt cached; the probe sources
live as Cortex artifacts `probe/<name>.rb` (map `current`). Claim
identifiers below refer to the Cortex artifact `scout-gear/entity-system.md`
(map `current`), which holds the full evidence chains.

All probes ran in a plain Ruby environment (bwrap sandbox, no forks;
concurrency probes use threads only), each standalone under
`timeout 60`. Concurrency claims are MRI/GVL-scoped. The behaviors were
re-verified against HEAD `8a3a514` before promotion into the two doc
pages; the live-code defects listed at the end were **not** promoted and
are Improvements candidates.

## Summary of findings

1. **Entities are plain Strings/Arrays with module annotations.** `setup`
   annotates in place and returns the same object; a second module
   stacks. `Entity::Object` adds exactly four instance methods
   (`entity_classes`, `base_entity`, `_ary_property_cache`,
   `all_properties`); `all_properties` is the union over stacked modules.
   *(C03, C06)*
2. **`properties` stores the arity signature, not the block.**
   `properties[name] = block.parameters`; only non-`:both` types get a
   generated public wrapper. *(C07)*
3. **Six dispatch types, two of them aliases.** `:single2array` installs
   `_single_` and `:array2single` installs `_ary_`, with the same public
   wrapper dispatch as `:single` / `:array`. *(C01)*
4. **Array-property dispatch has a per-container cache keyed by
   name+args.** The entity module is not part of the key, so a second
   module annotating the same array reuses the first module's entry; the
   `||=` fill is not atomic under concurrent cold access. *(C07, C15)*
5. **Persisted properties are cached per entity id and per argument
   set.** `obj.id` digests value + annotations, so a different
   `format`/`namespace` is a different entry; there is no recompute on
   age without a `:check` file, and `unpersist` leaves the file on disk. *(C13)*
6. **`Entity.formats` registration is first-write-wins and silent**, with
   cached `(format)`-decoration lookup and whole-cache invalidation on
   `[]=`; stable-key reads survive concurrent churn on MRI, lost-update
   registration does not. *(C08, C09, C14)*
7. **Identifier translation prefers the first usable file and chains
   before failing.** *(C12)*
8. **`prepare_entity` returns unknown types unchanged, dups the three
   annotatable types, and ignores `format:` for non-`Identified`
   modules.** *(C11)*
9. **TSV integration is narrow**: `traverse` with `:single` values and
   `NamedArray#[]` field access are the only entry points that produce
   entities; `TSV#sort_by` returns unannotated keys. *(C02, C05)*
10. **`EntityWorkflow` declares two properties per task** (`<name>_job`
    and `<name>`); the `job` property is `:both`. *(C10)*

## Probe ledger

### `entity_annotations_and_extension`

- **Probed**: the annotation surface of `extend Entity` alone vs
  `include Entity::Identified`, module stacking on a second `setup`,
  whether `format:` reaches a non-`Identified` module, and the
  `Entity::Object` instance surface.
- **Finding**: `extend Entity` registers the module name in
  `Entity.formats` and no annotations; `Entity::Identified` adds
  `:format`/`:namespace` plus `to`/`name`/`default`. Stacked setups
  accumulate in `annotation_types`. `format:` is ignored for
  non-`Identified` modules.
- **Receipt**: `Observation/probe/entity_annotations_and_extension_503acb370d8b76e6d1b20a99dc9284bc.json`
- **Claims**: C03, C06, C11 (format-option half)

### `entity_ary_property_cache_concurrency`

- **Probed**: thread-concurrency of the container-level
  `_ary_property_cache` fill (`cache_code = Misc.digest({name:, args:})`,
  `container._ary_property_cache[cache_code] ||= ...`) plus the
  sequential cross-module hazard implied by the key.
- **Finding**: `||=` is not atomic — under concurrent cold access the
  block runs more than once and losing readers get equal values in
  distinct objects; the uncontained-singleton path bypasses the cache;
  the digest omits the entity module, so a second module annotating the
  same array sequentially reuses the first module's entry.
- **Receipt**: `Observation/probe/entity_ary_property_cache_concurrency_716bc268ff148f3ffc4e269c5b98042b.json`
- **Claims**: C15, C07 (cache-key half)

### `entity_consumers_integration_points`

- **Probed**: where the Entity layer is consumed across scout-gear
  (`traverse.rb:80`, `util/sort.rb`, `KnowledgeBase`, `Association::Item`,
  `EntityWorkflow`), read from the live checkout.
- **Finding**: the observable TSV entry points are exactly
  `traverse` with `:single` values and `NamedArray#[]` field access;
  KB consumes `Entity.formats` lookups and `prepare_entity`;
  `Association::Item` uses `Entity.identifier_files`.
- **Receipt**: `Observation/probe/entity_consumers_integration_points_5e8048c14f8c226e12f0ea115a09b8b9.json`
- **Claims**: C02, C05 (consumer inventory)

### `entity_format_registry`

- **Probed**: `Entity::FormatIndex` registration via `format=` and
  `add_identifiers`, the `find` algorithm (exact key, `to_s`, paren
  decoration, caching), `[]`/`include?`/`[]=` cache invalidation, and
  format collisions.
- **Finding**: first registrant wins (`||=`); decorated fields such as
  `"Associated Gene Name (Hsa)"` resolve to the paren-less registered
  key; `[]=` clears the whole `@find_cache`.
- **Receipt**: `Observation/probe/entity_format_registry_a1b43a2f5f931fe0732c3f3aa79192e8.json`
- **Claims**: C08, C09

### `entity_formats_registry_concurrency`

- **Probed**: thread-concurrency of the process-global `Entity.formats`
  registry — stable-key reads under concurrent writers, the
  negative-cache race, first-write-wins under churn, and cache-object
  replacement.
- **Finding**: a reader looking up an already-registered key cannot be
  lost (worst case it takes the slow path); `[]=` replaces `@find_cache`
  with a new object; a first-time read racing a first-time registration
  of the *same* key can be lost (lost update).
- **Receipt**: `Observation/probe/entity_formats_registry_concurrency_1907f6e5e8bf7cf4ca1af80e698e4b94.json`
- **Claims**: C14

### `entity_formats_registry_semantics`

- **Probed**: exact and parenthesized-decoration lookup, module-vs-string
  keys, symbol lookups, mutation cache invalidation, collisions between
  modules, empty-string formats.
- **Finding**: plain-name match short-circuits before the paren scan, so
  `"DrugBank (~misc)"` stays nil — the paren must be the exact key's
  form; empty-string formats register but are unusable.
- **Receipt**: `Observation/probe/entity_formats_registry_semantics_fbbaeda19a16bff0e20c5d6995a30523.json`
- **Claims**: C09

### `entity_identifier_translator_selection`

- **Probed**: how translation picks among multiple translator files for
  the same source/target, the `NAMESPACE` tag substitution, and the
  `Persist.memory` memo in `identifier_index`.
- **Finding**: the first file yielding a usable index wins; a direct file
  beats a two-step chain only by being first; when no file covers the
  pair, a chained translation is preferred over raising.
- **Receipt**: `Observation/probe/entity_identifier_translator_selection_839425332d7d001d28f18a1dc50c8556.json`
- **Claims**: C12

### `entity_identifiers_translate`

- **Probed**: `add_identifiers` header-driven format registration, the
  `NAMESPACE` glob convention, the `@formats`/`@default_format`/
  `@name_format`/`@description_format` accessors, and instance `to`.
- **Finding**: every header field becomes a format of the module; `to`
  keeps the entity type and gains the target format; the index is
  memoized per (type, target, source).
- **Receipt**: `Observation/probe/entity_identifiers_translate_4b17eee6701280ff36361903faf3a3e3.json`
- **Claims**: C12 (setup half)

### `entity_in_tsv_traversal`

- **Probed**: how entity conversion is wired into TSV row delivery
  (`traverse.rb` ~76-84, `util/sort.rb`).
- **Finding**: values are converted only when `! unnamed && fields`;
  `:flat`/`:single` uses `prepare_entity(values, fields.first)`, all
  other types use `NamedArray.setup` (lazy per-`[]`); the key is never
  converted; `TSV#sort_by` returns unannotated keys (annotation happens
  inside the comparison only); `entity_options` does not add a
  `namespace` annotation of its own.
- **Receipt**: `Observation/probe/entity_in_tsv_traversal_f32b0d4a06f49555d477af36a0366b16.json`
- **Claims**: C02, C05

### `entity_namedarray_and_object`

- **Probed**: the scout-gear additions to `NamedArray` and the
  `Entity::Object` core instance methods.
- **Finding**: `NamedArray#[]` with a string field name prepares the
  value as an entity; integer access keeps raw behaviour but re-resolves
  the field name when the integer is a valid position;
  `entity_classes`/`base_entity`/`_ary_property_cache`/`all_properties`
  are the whole `Entity::Object` surface.
- **Receipt**: `Observation/probe/entity_namedarray_and_object_f2d8c07fa14238778a176e1604a2ede7.json`
- **Claims**: C02, C03

### `entity_namedarray_field_lookup`

- **Probed**: the 13-line `entity/named_array.rb` in isolation.
- **Finding**: position resolution delegates to
  `NamedArray.identify_name`; the value is then run through
  `Entity.prepare_entity` with the field name as the format key; a
  non-field Integer falls back to plain Array access; unregistered field
  names return the raw value.
- **Receipt**: `Observation/probe/entity_namedarray_field_lookup_3acc699cd3c67acfd875f8557787a252.json`
- **Claims**: C02

### `entity_object_load_lifecycle`

- **Probed**: the lifecycle claims the user doc makes about loading
  persisted property values — `load`, `Entity::LoadError`, and the
  relation between entity id/name/setup and the cache keys.
- **Finding**: neither `load` nor `Entity::LoadError` exists anywhere in
  `lib/` or `test/` (grep: zero hits); `Entity::Object` has exactly the
  four methods above. The task brief's "load lifecycle" language was the
  hallucination risk, not the code.
- **Receipt**: `Observation/probe/entity_object_load_lifecycle_036a9e694027ae8d819ca77e0b6442c8.json`
- **Claims**: C03

### `entity_persist_annotation_repo_layout`

- **Probed**: `Persist.annotation_repo_persist` as used by
  `Entity::Property.persist` with `:annotation` + `annotation_repo`.
- **Finding**: the repo must be a String path (an Array crashes on
  `repo.fields`); repo fields are fixed
  `["literal","annotation_types","JSON"]` keyed by `"Annotation ID"`;
  array-valued properties crash the path with `NoMethodError` — root
  cause in the top-level `Annotation` helpers
  (`lib/scout/tsv/annotation.rb`, `load_tsv_values`/`obj_tsv_values`).
- **Receipt**: `Observation/probe/entity_persist_annotation_repo_layout_e46fc37321c4b8eaae7c328bd1ae05ef.json`
- **Claims**: C04

### `entity_persisted_property_invalidation`

- **Probed**: which entity properties get persisted, where, and what
  triggers a recompute.
- **Finding**: path composition is `[name, obj.id] * ":"` under
  `Entity.entity_property_cache[Module][property]`; `obj.id` is the
  digest of value + annotation info, so annotation changes produce new
  entries rather than invalidations.
- **Receipt**: `Observation/probe/entity_persisted_property_invalidation_9571c8bf2dcfadc235f254e49ebd4600.json`
- **Claims**: C13 (identity half)

### `entity_prepare_entity_semantics`

- **Probed**: `Entity.prepare_entity(entity, field, options)` — identity
  vs duplication, frozen inputs, Array inputs with `AnnotatedArray`,
  `dup_array`, Numeric receivers, module-vs-format-string field, unknown
  formats, and stacking on re-prepare.
- **Finding**: returns the entity unchanged unless String/Array/Numeric;
  always dups those three (frozen included); `format:` only reaches
  modules that declare it; arrays always get `AnnotatedArray`;
  `dup_array: true` dups elements; unknown fields return the plain value;
  re-preparing stacks modules.
- **Receipt**: `Observation/probe/entity_prepare_entity_semantics_a9240a17213da91fe1d5d730d242d385.json`
- **Claims**: C11

### `entity_property_dispatch`

- **Probed**: the name-or-hash DSL, the four primary dispatch types, the
  `_single_`/`_ary_`/`_multi_` real-method convention, single vs array
  receivers, the per-container cache, and the class-level `properties`
  registry.
- **Finding**: real-method naming and wrapper re-dispatch behave as
  documented; the container cache is filled once per (name, args).
- **Receipt**: `Observation/probe/entity_property_dispatch_7106db5feb561c35dca07089d7b4d566.json`
- **Claims**: C01 (superseded in coverage by the matrix probe)

### `entity_property_dispatch_matrix`

- **Probed**: the complete dispatch matrix for all six types — real
  method, String receiver result and `self` inside the block, Array
  receiver result, block executions per call.
- **Finding**: `:single2array` ≡ `:single` and `:array2single` ≡ `:array`
  down to the installed method name and wrapper dispatch; `:both` is the
  only type whose public name *is* the block.
- **Receipt**: `Observation/probe/entity_property_dispatch_matrix_b77805514c09101f86d16792549ce9ad.json`
- **Claims**: C01

### `entity_property_multiple_and_containment`

- **Probed**: `:multiple` batch semantics (block sees an annotated array,
  receiver-order preservation, per-item persistence marker) and the
  container-cache path for `:array` properties invoked on a contained
  element.
- **Finding**: the batch runs once and is shared by `container_index`;
  an uncontained single entity runs the block every call;
  `:multiple` on a `:single`-typed array receiver dispatches per element.
- **Receipt**: `Observation/probe/entity_property_multiple_and_containment_908711371022fe29f6aa902f6f8e15e5.json`
- **Claims**: C07

### `entity_property_persist_and_cache`

- **Probed**: the default `entity_property_cache` path, the per-module
  per-property directory, the `persist` defaults, `persisted?`,
  `unpersist`, the `MultipleEntityProperty` sentinel, and
  `:annotation`/`annotation_repo` routing.
- **Finding**: defaults `persist: true, dir: <cache>/<Module>/<name>`;
  `unpersist` removes the registration only; the sentinel implements
  per-item persist inside `:multiple` dispatch. (Executed at a probe
  version whose content was later superseded by
  `entity_persisted_property_invalidation`; kept for the routing facts.)
- **Receipt**: `Observation/probe/entity_property_persist_and_cache_88ed8365f54d5fbdc77e003fbe4f6f14.json`
- **Claims**: C13 (routing half)

### `entity_property_persist_annotations`

- **Probed**: how persisted `:annotation`-type properties interact with
  an `annotation_repo`, and how repeated/other-entity calls fill it.
- **Finding**: entries are keyed `"<name>:<entity id>"`; values round-trip
  with their annotations; the repo grows one entry per entity. Array
  values take the crash path recorded by
  `entity_persist_annotation_repo_layout`.
- **Receipt**: `Observation/probe/entity_property_persist_annotations_b7d26837609470ae059b3ad820024eae.json`
- **Claims**: C04

### `entity_property_registration_surface`

- **Probed**: the registration surface beyond dispatch — `properties`
  storing parameter lists, redefinition of the same name,
  `persist`/`persisted?`/`unpersist`, default dir shape, and what an
  unregistered property call does.
- **Finding**: `properties[name] = block.parameters` (arity signature,
  not the block); redefinition overwrites; default dir
  `var/entity_property/<Type>/<name>`; an undefined property raises
  `NoMethodError`, but a property defined on a sibling module is not
  visible.
- **Receipt**: `Observation/probe/entity_property_registration_surface_68ca7518189e9481e63c3083d250c7cb.json`
- **Claims**: C07

### `entity_types_in_kb_registry`

- **Probed**: the Entity-side half of KB entity registration — that
  `Entity.formats[format] = module` is what the `"Format=~Type"`
  association source syntax resolves through, and that
  `KnowledgeBase#get_entities` uses `prepare_entity` + `formats.find`.
- **Finding**: registering a format name for a module makes it resolvable
  both by exact name and by the decorated names KB passes.
- **Receipt**: `Observation/probe/entity_types_in_kb_registry_0f337a16a2bba32e92e3afe7eb86c310.json`
- **Claims**: C09 (KB consumer half)

### `entity_workflow_entity_task`

- **Probed**: the Entity-side facts of `EntityWorkflow` — what
  `extend EntityWorkflow` provides, the `:both` `job` property, the two
  properties `property_task` defines, and the `entity_name` default.
- **Finding**: `extend EntityWorkflow` gives Entity + Workflow +
  annotation-input registration; `property_task` defines `<name>_job`
  and `<name>`; the `entity`/`entity_list` helpers are registered as
  workflow helpers (default entity name `"entity"`), not as singleton
  methods on the module.
- **Receipt**: `Observation/probe/entity_workflow_entity_task_e12b0d259f4283c4236230692a71e3bd.json`
- **Claims**: C10

## Deliberately not promoted (live-code defects)

These are behaviors of the code that the docs now describe *as
workarounds* or not at all, because documenting them as normal behavior
would freeze a defect. Improvements.md candidates:

- `Entity.formats` collisions are silent (`||=`): the losing module is
  undiscoverable after the fact. *(C09)*
- `annotated_array: false` in `Entity.setup` is dead: the guard
  `! options[:annotated_array] == FalseClass` is never true, so
  `AnnotatedArray` is always extended. *(C11)*
- `entity_options` passed to `prepare_entity` does not add a `namespace`
  annotation; namespace must come from the module or an explicit setup
  option. *(C05)*
- `:annotation`-repo persistence of array-valued properties crashes
  (`NoMethodError` in the top-level `Annotation` helpers) — root cause
  and fix sit on the TSV/Annotation boundary, other owner. *(C04)*
- `entity/named_array.rb` and `entity/object.rb` were previously
  documented nowhere.
