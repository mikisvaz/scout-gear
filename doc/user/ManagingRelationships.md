# Managing Relationships

This document explains how to represent and query relationships between
entities using the Association and KnowledgeBase subsystems.

It covers: registering associations, declaring source/target entity types
and formats, building persisted indexes, and querying related entities.

## Overview

### Association

An association is a TSV file (or TSV object, or block that produces one)
that links two entity types. Registering it builds a lookup index — a
TSV whose key is `source~target` pairs. Two artifacts are built and they
differ: the *database* (`Association.database`, `type: :double`, keyed by
the source field, with target plus extra fields as values) and the
*index* (`Association.index`, a pair-keyed `type: :list` TSV stored
inside a `TokyoCabinet::BDB` file) — see
[What registration builds](#what-registration-builds).

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

Source/target use the syntax `"<field name>=><format>"` or
`"<field name>=~<entity type>"` (the two suffixes may be combined):

- `"Ensembl Gene ID=~Gene"` — Ensembl-format Gene entities.
- `"Uniprot Accession=~Protein"` — Uniprot-format Protein entities.

The format part is used for identifier translation; the entity-type part
(what follows `=~`) selects the Entity module used to annotate results
(association/fields.rb). Entity types are resolved through
`Entity.formats` (see [Working with Entities](WorkingWithEntities.md)),
so a type that is not a registered format simply leaves the ends as
plain Strings instead of raising.

An unknown *field name* does not fail at registration. Two shapes must
be distinguished:

- the spec is a field name that is simply not in the file (`"Name"`,
  `"Nonexistent field"`): it is carried through unchanged, and the
  failure surfaces when the index is built — `TSV.identify_field`
  returns `nil` for it and `Association.headers` raises
  `NoMethodError: undefined method '+' for nil` (association/fields.rb);
- the spec names a *registered format* (`"Person"`) whose entity type
  has fields in the file: `extract_specs` rewrites it to the first field
  of that entity type (`"Person"` → `"Child (Alias)"` when
  `Entity.formats['Person'] == Entity.formats['Child (Alias)']`; a bare
  `"Name"` that is *not* a registered format keeps the `"Name"`
  literal). If no field of the file maps to that format, it raises at
  once `Source not found [...]` / `Target not found [...]`.

The parser (`Association.parse_field_specification`) understands three
forms, combinable: `field`, `field=~Type`, `field=>Format` — `=~` names
the *entity type*, `=>` names the *identifier format*. Integers are field
positions. `=>Format` and `=~Type` alone (implicit field nil) are also
accepted. `Field name (Format)` is **not** parsed: the parenthesised
suffix is simply part of the field name here (it resolves only when a
format literally named that way is registered), and the plain
`source:`/`target:` option form (`source: '=>Initials'`) selects a field
by format name. Both are shapes inherited from rbbt; downstream
workflows still written against rbbt use them.

### Identifier translation at registration

`Association.index`/`Association.open` accept `source_format:` /
`target_format:` (or a `format:` map from entity type to format); the
same translation can be spelled in a field spec as `field=>Format`. When
a side is translated, its values are rewritten through a
`TSV.translation_index` built from the registered identifier files plus
`Entity.identifier_files(format)`, and the corresponding header becomes
`<base> (<format>)` — the base is the field name with any parenthesised
part stripped, so `Child (Alias)` translated to `Name` becomes
`Child (Name)` (and translating to `Alias` yields `Child (Alias)`
again, unchanged). The index `key_field` is built from those headers.
Rows whose id cannot be translated are **dropped** (`UnknownName` is
absent from the resulting index). A header with no parenthesised part is
renamed to the format alone (`Name` → `Alias`); one that has it becomes
`<base> (<format>)` (`Child (Alias)` → `Child (Name)`); translating to
the format the header already names leaves it unchanged. A format pair
with no identifier file between them raises
`Could not traverse identifier path from 'X' to 'Y'` (the identifier
files are the kb's `identifier_files` plus those registered in
`Entity.formats` for the source format).

### Traverser

The Traverser (`kb.traverse`) is the query engine that follows
associations. It understands a rule language of the form
`SOURCE DATABASE TARGET`, e.g.:

```ruby
kb.traverse ["Miki brothers ?1"]
```

The assignments hash of that rule is `{"?1" => [...]}`.

Rule element forms (traverse.rb):

- literal entity — a single id (`"Miki"`, identified through the
  database identifiers — `"001"` resolves to `"Miki"`), or an `"A~B"`
  pair key. A pair key as the *source* selects the pairs themselves, so
  it only contributes matches when a rule's own database contains those
  exact keys; it does not expand to each end.
- `?name` — wildcard, bound by earlier rules and carried forward;
- `:name` — named list, resolved with `kb.load_list(name)`, only valid in
  the source or target position;
- `?@name` — a wildcard over the databases registered **in this kb**.
  `id_dbs` expands it to every database registered locally that carries
  no `@` suffix at all (the name after the `@` is not used as a filter
  for the plain form), and it does **not** need to be bound first: an
  unbound `Miki ?@first ?1` iterates every registered database of this
  kb and returns the union of the matches (`{"?1" => [...]}`), while the
  database wildcard itself (`?@first`) never appears in the assignments.
  `@?` alone is not a recognised form (`Rule not understood: @? ?1`),
  and `:?name` is a *named list* (`kb.load_list`), not a database
  wildcard: `Miki parents :?1` raises `List not found ?1`.
- `DATABASE@kb` — a database of *another* kb. scout-gear has no public
  API to attach a second KnowledgeBase, so the alias is only resolved
  among the names registered **in this kb**: it matches a locally
  registered `name@kb` database
  (`kb.register 'parents@kb', file, source: ..., target: ...` — then
  `Miki parents@kb ?1` traverses it like any other database) and
  otherwise raises `Repo <name> not found and not registered`
  (`brothers@kb` with only `:parents`/`:brothers` registered). A locally
  registered alias still needs working `source:`/`target:` specs, or
  id translation between the databases fails with
  `Could not traverse identifier path`;
- trailing `- conditions` — `field=value` conditions over the
  AssociationItem info fields (`'Type of parent=father'`). The whole
  condition must be quoted so that a field name containing spaces stays
  one token; the field name is the AssociationItem *info* field (see
  [AssociationItem](#associationitem)). The value is interpreted by
  `Misc.match_value`: a plain string compares for equality (case-sensitively: `FAther` matches
  nothing) and `/regexp/` matches the pattern (`/father|mother/` covers
  several values). Conditions that are not `key=value` fall back to a
  truthiness test of the info value; over a field whose values are the
  strings `true`/`false`, a bare `Flag` keeps only the `true` ones while
  `Flag=true`/`Flag=false` compare as strings and match exactly.
  Comparison and negation conditions never match string values: the
  value is coerced numerically, so `field>0` on `Type of parent` (and on
  a numeric `Score` field) yields nothing, as does `Score!=5`.
  Bar-separated alternates are **not**
  supported: `Misc.tokenize` splits the condition on `|` before the `=`
  is even examined, so `field=father|mother` becomes two tokens, each of
  which falls into the bare-field (truthiness) branch — matching nothing.
  Use a regexp (`field=/father|mother/`) instead.

`kb.traverse(rules)` returns `[assignments, paths]`: the bound wildcards
and an array of per-rule match chains. `kb.traverse(rules, true)` skips
path reconstruction and returns `nil` for the paths; the assignments are
still populated. An unregistered database name (including `!db` reverse
forms inherited from rbbt) raises `Repo ... not found and not
registered`. Rules are matched with
`/([^\s]+)\s+([^\s=]+)\s+([^\s]+)(?:\s+-\s+(.*))?/`: `=` is not
allowed inside the source or database tokens, and a fourth token
without a `-` separator is not an error — it is treated as
`SOURCE DATABASE TARGET` + junk, so the rule `"not a rule at all"` dies
with `Repo a not found and not registered` (the third word becomes the
database name) rather than being skipped. A rule that matches *no*
branch at
all — for instance a two-token rule — raises
`Rule not understood: <rule>`. Two further forms exist beyond the
three-token rule:

- `?var = value, value` — an assignment rule; `var = db value, value`
  first identifies the values through the named database. The values are
  split on `,`; each is looked up in `assignments` first, then passed to
  `identify`. Rules of this shape always run through the
  path-reconstruction machinery, so call `traverse` with `nopaths`
  (`kb.traverse(["?1 =parents Miki"], true)` → `{"?1" => ["Miki"]}`).
- `?var {` … `}` — an assignment block: `?var {` opens it and `}`
  closes it, discarding the accumulated paths and keeping only the
  `?var` matches. Like the assignment rule it runs through the path
  machinery, so call it with `nopaths`
  (`kb.traverse(["?1 {", "Miki parents ?1", "}"], true)`).

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
| `:fields` | Info fields to carry into the index (defaults to every field other than source and target) |
| `:undirected` | Treat the association as undirected |
| `:persist` | Persist the index/databases (a flag or a path; engine is fixed) |

Association indexes and databases always persist through
`TokyoCabinet::BDB`; the `:persist` option controls *whether* and *where*
the artifact is built/reused, it does not select the engine (see
[Persistence Engines](../developer/PersistenceEngines.md) for the general
engine list).

### What registration builds

`kb.register` itself only appends `[file_or_block, options]` to an
in-memory registry; nothing is read from disk yet (registry.rb:5-20).
The artifacts are built lazily by the first `get_index`/`get_database`/
query call. Re-registering the same name replaces the entry — but the
lazy artifacts are memoised per kb instance (`Persist.memory`), so a
re-register does **not** rebuild an index that was already built in the
same process (`kb.get_index(:x)` after a re-register returns the *old*
object). A block registration stores the block itself (given a
`filename` singleton method returning the name); a TSV object or a block
cannot be serialized to a path, so it only lives for the process.

The artifacts are materialised on demand, each by its own first use
(get_index builds `<dir>/<name>`; get_database additionally
`<dir>/<name>.database`; the first `parents` query `.reverse`):

- `<dir>/<name>` — the **index**: `Association.index` output, a
  pair-keyed TSV (`key_field` `"<source field>~<target field>"`, values
  of `type: :list` holding the extra `:fields` only) stored in a
  `TokyoCabinet::BDB` file (association/index.rb).
- `<dir>/<name>.database` — the **database**: `Association.database`
  output, the reordered source TSV (`type: :double`, key = source field,
  fields = target + extras).
- `<dir>/<name>.reverse` — the reverse index, built on demand by the
  first `parents` query, a sibling BDB with flipped keys
  (`Association::Index#reverse`).
- `<dir>/lists/<Entity|simple>/<id>` and `<dir>/config/{registry,
  entity_options, identifier_files, namespace}` — lists and the
  `kb.save`/`kb.load` configuration (see below).

`kb.get_index(name)` returns the index (the pair-keyed `:list` TSV), not
the database. Registering a TSV object or a block instead of a path
means nothing on disk can back a later reload, so such an entry is
rebuilt from the in-memory TSV in every fresh process.

### Undirected associations

`:undirected` defaults to **true when the source and target field
headers are equal** (`undirected = true if undirected.nil? and
source_field == target_field`, association/index.rb:22). An undirected
index records *both* `A~B` and `B~A` keys and appends a third
`~undirected` segment to the key field. Undirectedness is read back from
that key_field marker (`kb.undirected(name)` is `pair(name).length == 3`),
so it survives save/reload rather than coming from the registration
options.

Because both orientations are stored, an undirected database answers
from either end through either accessor: `kb.children(:brothers, 'Clei')`
gives `Clei~Guille` and `kb.parents(:brothers, 'Guille')` gives
`Guille~Clei` (annotated `reverse: true`). `children` and `parents`
therefore differ only by annotation, not by reachability. Note that the
two *field headers* still differ (`Older (Alias)`/`Younger (Alias)` in
the shipped fixture), so the default above only bites when they are
literally equal.

## Querying relationships

### Direct lookups

```ruby
# children/parents for a node (query.rb)
kb.children(:geneprotein, "ENSG00000141510")  # source -> target
kb.parents(:geneprotein, "ENSP00001")         # target -> source
kb.neighbours(:geneprotein, "ENSG00000141510") # => {parents: [...], children: [...]}

# subset: all matches for a set of nodes; returns an AnnotatedArray
# of AssociationItem (query.rb:15)
kb.subset(:geneprotein, :all)                 # every pair in the index
kb.subset(:geneprotein, {source: ["ENSG00000141510"], target: :all})
kb.subset(:geneprotein, {source: :all, target: ["ENSP00001"]})
kb.all(:geneprotein)                          # all keys, no filtering

# count is NOT a KB method; use subset(...).length or traverse matches
```

`kb.subset(name, entities)` accepts `:all`, a **Hash**, or an
**AnnotatedArray**. Hash keys are resolved by `select_entities`
(entity.rb:5-19) in this order: `:source` / `:target`, the *field name*
of either side (`"Ensembl Gene ID"`), the entity type name registered in
`Entity.formats` for that field, and finally `:both` (a `:both`-only
selection pairs every member of the array against itself, so an array of
source ids alone yields `[]`). An AnnotatedArray is turned into
`{"<format or base_entity>" => entities}` — the key it produces is
usually the entity type, i.e. the `:both` case above; pass a Hash with a
`:source`/`:target`/field-name key instead when only one side is
restricted. A plain String or Array raises
`RuntimeError: Entities are not a Hash or an AnnotatedArray` — a single
id must be wrapped (`{source: [...]}`) or queried through
`children`/`parents`. Identification is **opt-in** for `subset`: the
keys `:identify` / `:identify_source` / `:identify_target` are read out
of the *entities* Hash itself (merged with the options), so pass them
alongside the selection — `kb.subset(:parents, {source: ['001'], target:
:all, identify_source: true})` — to translate ids through the registered
identifier files before matching. Both sides must be given: an
unspecified side resolves to `nil` and `subset` returns `[]` without
error, so `{source: [...]}` alone yields nothing. Note the `identify_*`
keys are read from the entities Hash, *not* from the second `options`
argument — `subset(name, entities, options)` passes `options` on to
`get_index`, where an `:identify_source` keyword raises
`unknown keyword` — so pass them inside the Hash even when you also give
options.

A `:target`-only selection (`{source: :all, target: [...]}`) is served
from the reverse index and the keys are flipped back, so the returned
items keep the source-first orientation (`subset({source: :all, target:
['Juan']})` → `["Isa~Juan", "Miki~Juan"]`). An empty or nil side yields
`[]` rather than an error.

Both `children` and `parents` identify their argument through the
database identifiers first (`identify_source`/`identify_target`), so an
id in any registered format works (`"001"` behaves like `"Miki"`,
`"005"` like `"Juan"`, with the `person/identifiers` file registered);
unknown ids pass through
unchanged (an untranslatable id raises no error, it simply matches
nothing). `parents` builds and uses the reverse index and returns items
passed through `items.invert` (query.rb:74-81) unless the association is
undirected: the pair string is flipped back to source-first orientation
(`Isa~Juan` for `kb.parents(:parents, 'Juan')`) and `reverse` ends up
**false** again, so `source_entity` is the child and
`target_entity` its parent, and `source_type`/`target_type` keep the
un-swapped field names (`Child (Alias)`/`Parent (Alias)`). Only the
*pre-invert* annotation is `reverse: true`; undirected indexes skip the
invert entirely. For an *undirected* association the index holds both
directions, so `children` and `parents` differ only by annotation, not
by reachability.

`neighbours(name, entity)` returns `{parents: [...], children: [...]}`,
collapsing to `{children: [...]}` only for an undirected database whose
source and target fields are equal (query.rb:83-97).

`kb.source(name)` / `kb.target(name)` return the *field names* of the
index (`pair(name)[0]/[1]` from `get_index(name).key_field.split("~")`,
registry.rb:53-60) — not entity lists.

### Using Entity properties

Association results are annotated with the entity types declared in the
field specifications / `entity_options`, so entity properties apply. Two
independent lookups are involved. (1) The entity module is chosen from
the *field* — `source_type`/`target_type` resolve
`Entity.formats[Entity.formats.find(field_name)]`, so a `Person` whose
identifiers declare the `Child (Alias)` format is what makes
`matches.target_entity` answer `Person ===`. (2) Annotation *values*
(the `language: 'es'` of the example below) come only from
`kb.entity_options['Person']`; without it the entity is annotated but
the property reads `nil`. Registration itself (`source: '...=~Person'`)
annotates the type but not the options. The annotated value is still a
`String` — `Person === parents.first` is the test, not
`parents.first.class`:

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
index = kb.get_index(:geneprotein)   # pair-keyed TSV, type: :list, BDB-backed
index.keys.sample                    # => "ENSG00000141510~ENSP00001"
index["ENSG00000141510~ENSP00001"]   # => ["father"] - only the extra :fields values
index.source_field                   # => "Ensembl Gene ID"
index.target_field
index.match("ENSG00000141510")       # keys starting with "ENSG00000141510~" ([] on no match)
index.match([id1, id2])             # array argument: the union of the matches
index.subset(["ENSG00000141510"], ["ENSP00001"])  # both sides explicit
index.subset(:all, ["ENSP00001"])    # reverse scan, keys flipped back
index.reverse                        # persisted sibling "<path>.reverse"
index.filter("Type of parent", "father") # pairs whose extra field == value
index.filter("Type of parent", ["father"]) # value may be a list (any member matches)
index.filter("Type of parent")        # no value: pairs with a non-empty, non-'false' value
index.filter{|key, values| ... }       # block: [key, values] per pair (or values only,
                                       # when the block is given a field name first)
index.to_matrix("Type of parent")           # cells = field values
index.to_matrix{|item| 1 }                  # block receives the pair key
index.to_matrix("Type of parent"){|value| value.to_s.upcase }  # block per cell value
```

`to_matrix` keys the result TSV by the *source field* (`Child (Alias)`)
and makes every distinct target id a column; a pair absent from the
index yields a `nil` cell. With a `value_field` the block receives that
field's value, without one it receives the pair key itself.

## AssociationItem

`kb.subset` / `kb.children` / `kb.parents` return AssociationItems — the
`source~target` string annotated with `knowledge_base`, `database` and
`reverse` (association/item.rb:4-8). Useful properties:

- `source_entity` / `target_entity` — annotated entities at each end
  (array2single). The annotation module is looked up through
  `Entity.formats` on the field name; when that format is not registered
  the ends stay plain Strings. Annotated entities are still Strings:
  test module membership (`Person === item.source_entity`), not
  `.class`;
- `info` / `info_fields` — the info fields of the pair as a Hash
  (`{"Type of parent" => "father"}`); the index carries every field
  other than source and target unless `:fields` was given. `info` is an
  `array2single` property: over an array of items it yields one Hash per
  item, and an item whose key is missing from the index raises
  `No info for pair; not registered in index`;
- `name` — the two ends' entity `name` properties joined with `~`; when an
  end has no `name` property the plain id is used. `name` is the *entity*
  name (the annotation-level name, e.g. `Cleia~Guillermo` for
  alias-format ids), not the raw key: use the item itself (or
  `source`/`target`) for the literal ids. `full_name` —
  `"<database>:<name>"` (or plain `name` when `database` is nil);
- `invert` — swap ends and flip `reverse` (:both, item.rb:20-35);
- `part` — `[[source, target], ...]` partitions (:array2single);
- `tsv` — the items re-keyed as a TSV (`key_field`
  `<source field>~<target field>`, fields `[source, target, *info_fields]`);
- `filter` — select items by info field value: pass the info field and
  value list (`filter('Score', ['3', '5'])`), or a block over the item
  TSV row (`filter{|key, row| row.flatten.include?('3') }`). A block that
  always returns `true` is *not* "keep everything": the value list built
  by `TSV#select` is empty, so `filter` returns `[]`. Calling
  `filter('Score', '5')` with a bare String raises
  `NoMethodError: undefined method '^' for String` inside `TSV#select` —
  pass an Array;
- `incidence` — source × target boolean matrix TSV (key_field `Source`,
  fields = the sorted distinct ids appearing on either end of the item
  set, sources included). Passing a block replaces the `true` cells with
  the block's value, keeping the maximum when a pair occurs several
  times. For an undirected index every pair is seen twice, so both
  orientations land in the matrix (a `Clei~Guille` item yields
  `Clei→Guille` and `Guille→Clei` rows);
- `adjacency` — a `:double` TSV (key_field `Source`, fields `Target`)
  built from `incidence`: per source it keeps the `target => value` pairs
  whose cell is non-nil, zipped as `[[target,...], [value,...]]`. The
  target columns are the ones present in the *whole item collection*
  (the incidence fields), and a `false` cell *is kept* — `adjacency`
  filters nils, not falses. Over the full kb that yields the complete
  target set per source with `true`/`false` flags; over a `subset`
  restricted to one source it degenerates to that source's own targets.
  Use it as a boolean co-membership table, not as a plain edge list.

## Persistence

Association indexes can be persisted for fast reloading:

```ruby
kb.register :geneprotein, "data.tsv", persist: true
```

This builds the index/database artifacts on first load and reuses them on
subsequent loads (`:update: true` forces a rebuild). The storage engine
for associations is always `TokyoCabinet::BDB`; see
[Caching Data](CachingData.md) for persistence in general.

## Saving and loading a knowledge base

`kb.save` YAML-serialises the registry, `entity_options`,
`identifier_files` and `namespace` under `<dir>/config/`; `kb.load`
restores them. A restored registry re-opens an index that was already
persisted to disk through the `persist_path`-exists fast path. Build the
index (`get_index`/`get_database`/any query) **before** `kb.save` if the
kb is to be reloaded later: an entry that was never built has no
persisted artifact to re-open. A registered TSV object or block cannot be
serialized to a path at all.

`KnowledgeBase.load(...)` accepts a Path, a plain directory String, a
Symbol (roots the kb at `var/knowledge_base/<symbol>`), or a workflow
name (reuses that workflow's own knowledge base), and calls `kb.load`
itself. A bare `\w+` String is treated as a Symbol. Note that `load`
matches the Workflow case before the String case, so the `Workflow`
constant must be loadable when you call it — with only
`require 'scout/knowledge_base'` in scope it raises
`NameError: uninitialized constant KnowledgeBase::Workflow`; a full
`require 'scout'` first makes the plain-directory form work. Setting
`kb.namespace` does not create a `<dir>/<namespace>/` tree — it appends
an options digest to the index file name (`<dir>/parents_<digest>`) and
is itself recorded in the config. `KnowledgeBase.new(<symbol>)` keeps
the Symbol as the `dir` verbatim; use `KnowledgeBase.load` to expand a
symbol to `var/knowledge_base/<symbol>`.

`entity_options` merge per key, kb-level defaults *under* any
per-database `entity_options` given at registration (registration wins
per key, kb-level keys not overridden are kept), and the merged result
lands on the built index (so items inherit it). Entity type keys
used by `kb.define_entity_modules` must be **bare Ruby constant names**
(`"Kin"`). A fully-qualified key such as
`"Object::Kin"` only works when that constant already exists (the
`Object.const_get` lookup succeeds); when the module has to be *created*
the subsequent `Object.const_set` raises
`NameError: wrong constant name Object::Kin`. With a bare name
`define_entity_modules` creates `Object::<Entity>`, wires
`identifier_files` and registers every identifier header format into
`Entity.formats` (`Kin` gains `Name`, `Alias`, `ID`, ...).

## Lists

`kb.save_list(id, list)` writes `<dir>/lists/<type>/<id>`: under the
list's `base_entity` name for an AnnotatedArray (for association items
that is `AssociationItem`), under `simple` for a plain Array. Both
`save_list` and `load_list` take the id as a String — a Symbol id
raises `TypeError: no implicit conversion of Symbol into String` inside
`list_file` (the type argument is stringified, the id is not).
`kb.load_list(id)` returns an annotated array for typed lists and plain
Strings for `simple` ones; `kb.lists` is a Hash
`{entity_type => [ids]}` (`{}` before any list is saved). In a Traverser
rule `:id` may appear in the *source or target* position
(`"Miki parents :mylist"`) and is resolved
through `kb.load_list` — but never in the *database* position, where a
`:`-prefixed token is treated as a database name.

## Descriptions

`kb.description(name)` resolves in precedence order: the registered
`:description` option, else `<kb dir>/<name>.md`, else the `#/##`
structured README (`<kb dir>/README.md`, or the README next to the
registered association file) parsed by
`KnowledgeBase.parse_knowledge_base_doc`. `kb.markdown(name)` composes
a `# <Humanized name>` heading, blank line, `Source: <type> - <field>` /
`Target: <type> - <field>` lines (the `<type> -` prefix only when
`Entity.formats` resolves the field name to a registered format — with
no format registered the line is just `Source: <field>`), and the
description — e.g. for the shipped
`parents` fixture: `# Parents`, `Source: Child (Alias)`,
`Target: Parent (Alias)`, then the description text (`List parents.`,
`Type of parent: father or mother`).

Not present: `kb.enrichment`, `kb.register_index` and
`kb.register_organism` are rbbt KnowledgeBase API. The
`knowledge_base/enrichment.rb` file ships in the tree but is **not
required** by `lib/scout/knowledge_base.rb` (and its body requires rbbt
itself), so those methods simply do not exist here.

## Common mistakes

- **Wrong field specification format**: `=~` separates the field name from
  the entity type and `=>` from the identifier format. `field (Format)` is
  rbbt-only syntax — in scout-gear the parenthesised suffix is just part
  of the field name.
- **Passing a bare String/Array to `subset`**: `kb.subset` accepts `:all`,
  a Hash or an AnnotatedArray; use `{source: ...}`/`{target: ...}` for a
  single id.
- **Ids containing `~`**: `~` is the pair separator, so ids with a tilde
  cannot round-trip through index keys.
- **`entity_options` keys with a namespace**: use the bare constant name
  (`"Kin"`); `"Object::Kin"` only resolves when that constant already
  exists and raises `wrong constant name` otherwise.
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
- **Saving a kb whose index was never built**: `kb.save` alone does not
  persist any index, so a kb reloaded from that config raises
  `Repo <name> not found and not registered` when queried. Build the
  index before saving (see
  [Saving and loading](#saving-and-loading-a-knowledge-base)).
- **Expecting `enrichment`/`register_organism`**: they are rbbt
  KnowledgeBase API; scout-gear ships `knowledge_base/enrichment.rb` but
  does not require it.
- **Calling `kb.delete_list` on a missing id**: it raises
  `List not found <id>` (from `list_file`, list.rb:23) rather than
  returning a warning — check `kb.lists` first if you want to test for
  existence.

## See also

- [Working with Entities](WorkingWithEntities.md) — entity modules and
  annotation of results.
- [Processing Tabular Data](ProcessingTabularData.md) — the TSV layer
  underneath association files.
- [Caching Data](CachingData.md) — persistence usage.
- [Persistence Engines](../developer/PersistenceEngines.md) — engine list.
- [Using the CLI](UsingTheCLI.md) — the `scout kb` command family for
  the same operations from the shell.
- [Cookbook](Cookbook.md)
