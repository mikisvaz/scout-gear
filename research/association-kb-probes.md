# Investigation: Association / KnowledgeBase — Probe Findings

> **Non-normative.** This document is a working investigation with
> implementation details, code exploration notes, and hypotheses. Refer
> to `doc/user/ManagingRelationships.md` and
> `doc/developer/Architecture.md` for maintained documentation.

Consolidated record of the fifteen probes run against the Association /
KnowledgeBase layer (`lib/scout/association.rb`,
`lib/scout/association/{fields,index,item,util}.rb`,
`lib/scout/knowledge_base.rb`,
`lib/scout/knowledge_base/{registry,query,traverse,list,entity,description,enrichment}.rb`)
during the documentation-consolidation campaign. Each probe was executed
through `Observation/probe(<name>)` and its receipt cached; the probe
sources live as Cortex artifacts `probe/<name>.rb` (map `current`).
Claim identifiers below refer to the Cortex artifact
`scout-gear/association-kb.md` (map `current`), which holds the full
evidence chains. Claim ids are the numbered headings of that artifact
(`1.1` … `11`), cited as C1.1, C1.2, …

All probes ran in a plain Ruby environment with the `Person` entity and
`test/data/person/` fixtures (`brothers`, `parents`, `marriages`,
`identifiers`), each standalone under `timeout 60`, persist paths
redirected to a tmp dir. Every finding below was re-verified against
HEAD `8a3a514` before promotion into `doc/user/ManagingRelationships.md`
and `doc/developer/Architecture.md`; the live-code defects listed at the
end were **not** promoted and are Improvements.md candidates.

---

## Summary of findings

1. **Registration is lazy and in-memory.** `kb.register` stores only
   `[file_or_block, options]`; nothing touches the disk until the first
   `get_index`/`get_database`/query call, and the built artifacts are
   memoised (`Persist.memory`), so a re-register returns the same
   object. (C1.1)

2. **The kb dir layout is flat, not namespaced.** `<dir>/<name>` (index),
   `<dir>/<name>.database`, `<dir>/<name>.reverse` (built on demand by
   the first `parents`), `<dir>/lists/<Entity|simple>/<id>` and
   `<dir>/config/{registry,entity_options,identifier_files,namespace}`.
   The `var/knowledge_base/<namespace>/...` shape is rbbt's. (C1.2, C9.2)

3. **The storage engine is hardcoded.** `Association.index` and
   `Association.database` wrap `Persist.tsv(..., engine: "BDB")`, so
   `persist: :HDB` / `persist_engine: :HDB` do not select HDB; the
   index and database are always `TokyoCabinet::BDB`. (C1.3)

4. **Index vs database shapes differ.** The *database*
   (`<name>.database`) is `type: :double` keyed by the source field; the
   *index* (`<name>`) is `type: :list` keyed by `source~target` with the
   extra info fields as values. Docs that called the index
   "`type: :double`" described the database. (C1.4, C3.2)

5. **Undirectedness lives in the key_field.** `:undirected` defaults to
   true when the two field headers are equal, and `kb.undirected(name)`
   is literally `pair(name).length == 3` — the third `~undirected`
   segment of the key_field is the marker, so it survives save/reload.
   (C1.5, C1.6)

6. **Field specifications are `field`, `field=~Type`, `field=>Format`.**
   `=~` names the entity type, `=>` the identifier format; integers are
   positions; a missing spec falls back to key field = source, first
   value field = target; the legacy `Field name (Format)` parenthesised
   form is *not parsed* — the parentheses are part of the field name.
   (C2.1–C2.4)

7. **`Association.open` is where translation happens.** With
   `source_format:`/`target_format:` the keys/values are rewritten
   through a `TSV.translation_index` over the registered identifier
   files, the header is renamed to the format, and untranslatable rows
   are **dropped**. (C3.1)

8. **Index queries are prefix scans plus a persisted reverse.**
   `match(entity)` is `prefix(entity + "~")`; `subset(:all, ['Juan'])`
   goes through the reverse index and flips the keys back to
   source-first orientation; `~` is a reserved separator in ids.
   (C4.1, C4.2, C4.3, C4.5)

9. **The query API is index-level and identify-aware.** `children`
   matches the forward index, `parents` matches the reverse and inverts
   the items so the queried entity stays the target; `neighbours`
   returns both keys except for self-looping undirected databases;
   `subset` requires a Hash/AnnotatedArray/`:all` (both sides given);
   `kb.all(name)` is the cheap all-keys query; `children`/`parents`
   call `identify_source`/`identify_target` automatically so raw ids
   from other formats work. (C5.1–C5.5, C8.3)

10. **AssociationItem is the pair string + three annotations.**
    `knowledge_base`, `database`, `reverse`; `invert` flips ends and
    negates `reverse` (and reverses the array order for arrays); `tsv`,
    `filter`, `incidence`, `adjacency` are derived views. (C6.1–C6.3)

11. **The Traverser is a regex-driven rule engine.** Rules are
    `SOURCE DATABASE TARGET [- conditions]`; wildcards `?n` bind and
    carry forward, `:name` loads named lists, `?@kb` iterates a kb's
    registered databases, `DATABASE@kb` resolves only locally registered
    names (no second kb can be attached from the public API); conditions
    are `field=value` over item info fields with `Misc.match_value`
    semantics (regexp equality; comparison/negation only ever matches
    numeric values, so they never match string info fields), but **no
    bar-list alternates**. (C7.1–C7.3)

12. **Lists, entity_options, descriptions and save/load.** Lists are
    saved under the `base_entity` name (or `simple` for plain Arrays);
    `entity_options` merge kb-level *under* per-database (registration
    wins per key); `description`
    consults three sources in precedence order; `kb.save`/`kb.load`
    round-trip registry, entity_options, identifier_files and namespace
    through `<dir>/config/`. (C8.1, C8.2, C8.5, C9.1)

---

## Probe ledger

### `assoc_kb_registry`

Probed what `kb.register` builds: the registry entry shape, whether
registration performs I/O, whether the same name can be re-registered,
and the resulting kb dir tree.

Finding: `register` appends `[file_or_block, options]` to an in-memory
`@registry` IndiferentHash and does no I/O; the index/database are built
lazily by the first query and memoised, so a second `register` of the
same name yields the *same* built object. First use creates exactly
`<dir>/<name>`, `<dir>/<name>.database`, `<dir>/<name>.reverse` (on
`parents`), `lists/` and `config/`.

- Receipt: `Observation/probe/assoc_kb_registry_21d3fc2be01ba83dfb515fed5c0794c1.json`
- Claims: C1.1, C1.2, C1.4, C1.5

### `assoc_kb_disk_and_persist`

Probed the on-disk artifacts and the effect of the `:persist` /
`persist_engine` options: index class, persistence paths, config files.

Finding: the index is always `TokyoCabinet::BDB` — `persist: :HDB` and
`persist_engine: :HDB` do not select the engine, only whether/where the
artifact is built. `namespace` changes the index *file name*
(`<name>_<digest>`, because namespace is part of the index options), not
the directory.

- Receipt: `Observation/probe/assoc_kb_disk_and_persist_21125c577a946bef9679ce03b2958720.json`
- Claims: C1.3, C9.2

### `assoc_index_building`

Probed `Association.index` construction: key_field shape, `:fields`
subsetting, the `undirected` default, and how the undirected marker is
recorded.

Finding: `undirected = true if undirected.nil? and source_field ==
target_field` (association/index.rb), producing a
`A~B~undirected`-keyed index with both `A~B` and `B~A` keys when both
specs point at the same field; `:fields` keeps the pair fields plus the
named extras.

- Receipt: `Observation/probe/assoc_index_building_25b230d1e10662baf77ec9ce274ad8e3.json`
- Claims: C1.4, C1.5, C1.6

### `assoc_field_specs`

Probed `Association.parse_field_specification`, `extract_specs` and
`headers`: the accepted grammar, defaults for missing/partial specs, and
whether the legacy `Field name (Format)` form is interpreted.

Finding: the grammar is `field`, `field=~Type`, `field=>Format`
(combinable; integers are positions; `=~Type`/`=>Format` alone mean an
implicit nil field); missing specs fall back to key field = source,
first value field = target; a bare entity-type string is *ignored* as a
spec; the parenthesised legacy form is never parsed — the whole string
is the field name (it only resolves when a format literally so named is
registered, which the fixture does).

- Receipt: `Observation/probe/assoc_field_specs_b0138cd70c0123cbbd94a8fcb89a2372.json`
- Claims: C2.1, C2.2, C2.3, C2.4

### `assoc_open_translation`

Probed `Association.open` and `Association.database`: the plain reorder
without formats, key/value rewriting with `source_format:`/`target_format:`,
header renaming, and the fate of untranslatable rows.

Finding: without formats `open` is a plain reorder (key = source field,
fields = target + extras); with a format the side is rewritten through a
`TSV.translation_index` over `TSV.identifier_files(obj)` +
`Entity.identifier_files(format)` + `:identifiers`, the header becomes
`<base> (<format>)` (or the format alone when the original header has no
parenthesised part), and rows whose id cannot be translated are dropped.
`Association.database` is the persisted `:double`-typed BDB over `open`.

- Receipt: `Observation/probe/assoc_open_translation_5b1a05d7340a9bfa780083d0c2254e36.json`
- Claims: C3.1, C3.2

### `assoc_index_module`

Probed `Association::Index#match`, `#subset`, `#reverse`, `#filter`,
`#to_matrix` directly (without the kb query layer): prefix semantics,
orientations, the reverse artifact, and filtering.

Finding: `match(entity)` = `prefix(entity + "~")` (the `~` terminator
prevents a short id from matching a longer id's keys); `subset(:all,
:all)` → all keys; `subset(:all, ['Juan'])` uses the reverse index and
flips keys back to source-first; `subset(['Miki'], :all)` → prefix
matches; explicit both → intersection; empty/nil either side → `[]`
never an error; undirected dedup applies only in the explicit-target
branch. `reverse` builds a persisted `<index>.reverse` sibling with
swapped fields and the undirected marker preserved; `filter` matches
value-field intersections or takes a block; `to_matrix` is an
`incidence`-shaped TSV.

- Receipt: `Observation/probe/assoc_index_module_098e2c424f89008bda41f655945b27eb.json`
- Claims: C4.1, C4.2, C4.3, C4.4

### `assoc_index_match_subset`

Probed id assumptions of the index: `~` as a separator in entity ids and
the `undirected` reading of the key_field.

Finding: ids containing `~` cannot round-trip through pair keys (an
empty source field yields keys `a~`, `a~~`; `match`/`subset` on `a~b`
return nothing); `undirected` is read from the third key_field segment,
so it survives save/reload.

- Receipt: `Observation/probe/assoc_index_match_subset_46813493b9981a84f3ddb61db25fdb91.json`
- Claims: C4.5, C1.6

### `assoc_index_subset`

Probed the kb-level `subset` through the item layer: orientation
preservation, undirected behaviour both directions, and the `info` of
returned items.

Finding: `subset(:all, ['Juan'])` returns source-first literals
(`Isa~Juan`, `Miki~Juan`); for an undirected database `children` and
`parents` differ only by the `reverse` annotation, not by reachability;
item `info` zips the index fields with the values and raises when the
pair is absent.

- Receipt: `Observation/probe/assoc_index_subset_bb8b72bfc3038fe93b57576cbff79298.json`
- Claims: C4.2, C5.5, C6.1, C6.3

### `assoc_kb_query`

Probed the public query API: `children`/`parents`/`neighbours`/`subset`
/`all`, and the AssociationItem surface they return.

Finding: `children` = forward `match` + annotate; `parents` = reverse
`match` + annotate with `reverse: true` + `items.invert` (unless
undirected) so the queried entity stays the target; `neighbours` returns
both keys, collapsing to `{children: ...}` only when `undirected(name)
and source(name) == target(name)`; `subset` requires a Hash /
AnnotatedArray / `:all` (a String or plain Array raises
`Entities are not a Hash or an AnnotatedArray`), and every side left
`nil` filters everything out; `all(name)` returns the raw index keys
without subset filtering.

- Receipt: `Observation/probe/assoc_kb_query_dddb9f3ead06074db7f5ea143b0babdb.json`
- Claims: C5.1, C5.2, C5.3, C5.4, C5.5, C6.1, C6.2, C6.3

### `assoc_kb_traverse`

Probed the Traverser rule language: literal sources (with
identification), wildcards, named lists, `DATABASE@kb` and `?@kb`
syndication forms, reverse `!db`, conditions, and the return value with
and without paths.

Finding: rules are matched by `/^([^\s=]+)\s+([^\s=]+)\s+([^\s]+)(?:\s+-\s+(.*))?/`
(no `=` in source or database, so assignment rules fall to the next
branch, and trailing tokens beyond the third are simply ignored); a
literal single id is identified through the database identifiers
(`"001"` → `"Miki"`); `?n` wildcards bind and carry forward; `:name`
loads `kb.load_list`; `?@kb` iterates the kb's databases (the kb part is
ignored beyond the `?`) while `@?` alone does not; `DATABASE@kb` resolves
only among locally registered names (a second kb is not attachable from
the public API) and otherwise raises `Repo <name> not found and not
registered`; `!db` reverse forms raise the same error; conditions are
`field=value` over item info fields with `Misc.match_value` semantics;
`traverse(rules, true)` returns `[assignments, nil]`. Assignment
(`?var = db values`) and block (`?var {` ... `}`) rules exist as the
remaining two branches of the same dispatch; both go through the path
machinery and want `nopaths`.

- Receipt: `Observation/probe/assoc_kb_traverse_c1c50b0facbf9a452a37c5b80fbb0c63.json`
- Claims: C7.1, C7.2, C7.3

### `assoc_kb_lists`

Probed the list API: `save_list`/`load_list`/`list_file`/`lists`/
`delete_list`, typed vs plain lists, and missing ids.

Finding: an AnnotatedArray list is saved under its `base_entity` name, a
plain Array under `simple`; `load_list` returns an annotated Array for
typed lists and plain Strings for `simple`; missing ids raise
`List not found <id>` (from `list_file`, before the guard in
`delete_list` is reached); `lists` returns `{entity_type => [ids]}`;
`delete_list` on a present id removes it and returns the path array.

- Receipt: `Observation/probe/assoc_kb_lists_e74ff317a5260aa2a8c9a5d879895422.json`
- Claims: C8.1

### `assoc_kb_lists_desc`

Probed lists plus the entity_options merge and the rbbt-legacy registry
surface (`enrichment`, `register_index`, `register_organism`).

Finding: kb-level `entity_options` merge *under* any per-database
`entity_options` given at registration, and both land on the built index
(registration wins per key); `entity_options` persist in
`config/entity_options` and are restored by `kb.load`. The rbbt
KnowledgeBase API surface (`enrichment`, `register_index`,
`register_organism`) is absent: `knowledge_base/enrichment.rb` is never
required by `lib/scout/knowledge_base.rb` and `kb.enrichment` raises
NoMethodError.

- Receipt: `Observation/probe/assoc_kb_lists_desc_d8c20ff5d87149c593c70c77756360d4.json`
- Claims: C8.2, C8.7

### `assoc_kb_description`

Probed `kb.description`/`kb.markdown`/`documentation_markdown`: the
three description sources, their precedence, and the README chunk
parser.

Finding: `description(name)` returns (1) the registered `:description`
option, else (2) `<kb dir>/<name>.md`, else (3) a `#`/`##`-structured
README — `<kb dir>/README.md` or the README next to the registered
association file — parsed by `KnowledgeBase.parse_knowledge_base_doc`
(text before the first `#` = overall description; each `# Title` chunk
maps downcased title → body). `markdown(name)` composes
`# <Humanized name>` + `Source:`/`Target:` lines + the description.
`documentation_markdown` is dead code (nothing assigns `@libdir`, and it
references an undefined `file` local).

- Receipt: `Observation/probe/assoc_kb_description_00d1f4b4caa1ce9ee16d58bc3de652b7.json`
- Claims: C8.5, C8.6

### `assoc_kb_load_save`

Probed `kb.save`/`kb.load`: which variables round-trip, that the
restored kb rebuilds/loads its indexes, and the `KnowledgeBase.new`
argument forms.

Finding: `save_variable` YAML-serialises `@registry`, `@entity_options`,
`@identifier_files`, `@namespace` into `<dir>/config/*`; after `load`,
`get_index` works against the persisted artifacts;
`KnowledgeBase.new(:sym)` (Symbol/Workflow) is accepted and roots the kb
at `var/knowledge_base/<sym>` when loaded through
`KnowledgeBase.load(:sym)` (a bare `new` keeps the Symbol as the `dir`
verbatim). Re-verification addendum: `KnowledgeBase.load` rescues on the
`Workflow` case before the String case, so calling it after only
`require 'scout/knowledge_base'` raises
`NameError: uninitialized constant KnowledgeBase::Workflow`; the full
`require 'scout'` is needed for the plain-directory form.

- Receipt: `Observation/probe/assoc_kb_load_save_ccc5da7a36771863625a0de858b62c37.json`
- Claims: C9.1, C9.2

### `assoc_kb_identify`

Probed `identify_source`/`identify_target` and `define_entity_modules`:
translation of known/unknown ids, `:all`, arrays, and the entity-module
side effects.

Finding: `identify_source(name, entity)` translates through
`get_database(name).identifier_files` (the `:identifiers` option or kb
`identifier_files`); unknown ids pass through unchanged, `:all` passes
through, Arrays are translated element-wise; `kb.children` calls
`identify_source` automatically, which is why a raw id works as an
entity argument. `define_entity_modules` creates `Object::<Entity>`
modules wired with `add_identifiers` — the entity key must be a *bare*
constant name. Re-verification at the promotion HEAD **reversed the
original claim direction**: a bare `"Kin"` is the form that works
(`Object.const_get` fails, the rescue does `Object.const_set 'Kin'`), and
the qualified `"Object::Kin"` is the form that raises
`NameError: wrong constant name` (const_set rejects the `::`). The claim
artifact (C8.4) states the opposite; live code at this HEAD was followed.

- Receipt: `Observation/probe/assoc_kb_identify_fecef406d3b496adb70cd1a918be1a39.json`
- Claims: C8.3, C8.4

---

## Re-verification notes (promotion time)

Every finding promoted into `doc/user/ManagingRelationships.md` was
re-run against HEAD `8a3a514` with the same `test/data/person` fixtures.
Two claim statements needed refinement during re-verification:

- **C7.2 (bar-list conditions)**: the claim that
  `field=father|mother` "compares the whole value string (never equal)"
  holds, but re-verification showed `Misc.tokenize` splits the condition
  on `|` *before* the `=` check, so each alternative becomes a separate
  token and a `field=[a|b]` shape falls into the bare-field branch. The
  docs describe the observable outcome (no match) and point at regexp
  alternation instead of documenting the tokenisation.
- **C5.3 (`subset` identify keys)**: the `:identify*` keys are read from
  the entities Hash, not from the options argument; passing
  `identify_source: true` as a third `options` argument reaches
  `get_index` and raises `unknown keyword`. Re-verified; the docs now
  say to put the keys inside the Hash.
- **C7.1 (unparseable rules / String rules)**: a rule that does not match
  the three-token pattern is not silently skipped — a *four*-token rule
  without a `-` is parsed as `SOURCE DATABASE TARGET` plus an ignored
  fourth token, and `"not a rule at all"` therefore raises
  `Repo a not found and not registered` (the third word is taken as the
  database). Passing a bare String instead of an Array raises
  `NoMethodError: undefined method 'each' for String`.
  Corrected during promotion.
- **C8.2 (entity_options merge)**: the claim said "kb-level defaults
  merged under registration"; re-verified the precedence at this HEAD —
  registration `entity_options` win *per key*, kb-level keys that are
  not overridden survive (registry.rb merges kb-level keys under the
  per-database ones). Docs updated.
- **C1.2 (dir layout)**: re-verified that `get_index` alone creates only
  `<dir>/<name>`; `<name>.database` appears with the first
  `get_database`, `<name>.reverse` with the first `parents`. The docs
  describe the artifacts per-trigger.
- **C8.1 (typed list path)**: re-verified that an AnnotatedArray of
  association items saves under `lists/AssociationItem/`, and that a
  Symbol list id raises `TypeError` inside `list_file`. Docs updated.

## Deliberately not promoted (live-code defects)

Behaviors of the code that the docs now describe as workarounds or not
at all, because documenting them as normal behavior would freeze a
defect. Improvements.md candidates:

- `KnowledgeBase#delete_list` interpolates an undefined `user` variable
  in its guard and the "raise" is a bare interpolated String
  (list.rb:90). Re-verification at the promotion HEAD: the line is
  unreachable in practice, because `list_file` raises
  `List not found <id>` first (list.rb:23). The dead guard is still a
  defect worth cleaning up, but the *observable* behavior for a missing
  id is a proper `RuntimeError`, so nothing was documented as a silent
  success. *(C8.1, list.rb:23 and list.rb:90)*
- `KnowledgeBase#documentation_markdown` is dead: `@libdir` is never
  assigned (always `nil`, so it returns `""`), and if it were set the
  method would raise `NameError` on the `file` local. *(C8.6,
  description.rb:33-42)*
- `lib/scout/knowledge_base/enrichment.rb` is never required and
  requires rbbt internally; `kb.enrichment` raises NoMethodError. Same
  for the rbbt-only `register_index`/`register_organism` API. *(C8.7)*
- `AssociationItem._select_match` contains a typo (`elem === orif`,
  `orif` should be `orig`; association/item.rb:206) reachable through
  `AssociationItem.select`.
- The `repo brothers@kb not found` failure means `DATABASE@kb` in a
  Traverser rule can never reach another KnowledgeBase: there is no
  public API to attach one, so the syntax suggests a capability the
  code does not have. *(C7.1)*
- `Association::Index#subset` silently returns `[]` when either side of
  a Hash is unspecified — a typo'd key (e.g. `:soucre`) produces an
  empty result with no error. *(C5.3)*
- `define_entity_modules` only accepts *bare* constant names
  (`"Kin"`): a qualified `"Object::Kin"` reaches `Object.const_set` with
  a `::` in the name and raises `NameError: wrong constant name`, and
  entity keys that are not valid constant names are unusable. The
  qualified form is accepted by `Object.const_get` when the constant
  already exists, so the failure only appears on first creation. *(C8.4,
  re-verified with the direction reversed — see the ledger entry)*

## Deliberately left open

- **Concurrency**: no probe exercised concurrent index builds or
  `traverse` from two threads; the docs keep the existing "build indexes
  in advance or serialize writes" advice without adding new claims.
- **Enrichment internals**: dead code requiring rbbt, which is not on
  this machine; not probed.
- **TokyoCabinet availability matrix**: the engine is hardcoded to BDB
  for associations, so this reduces to the Persist engine claims in
  `scout-gear/persistence-engines.md`.
