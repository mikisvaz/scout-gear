# Identifier translation — the actual mechanism (final, source-verified)

Baseline: git 065c167. This document supersedes any earlier statement that
identifier files follow a `var/<namespace>/identifiers/<source>%to<target>`
layout. **That construct does not exist in scout-gear.** `grep -rn '%to'
lib/ bin/ scout_commands/` returns nothing; it appeared only in docs.

## 1. What an identifier file is

A plain TSV whose **header field names are the identifier formats** the
file maps between. Format pairs are not fixed when the file is defined;
which columns act as source and target is decided **at translation time**.

Repo fixtures:

- `test/data/person/identifiers` — header `#Name,Alias,ID`:
  one file, three formats (Name, Alias, ID).
- `test/data/person/brothers` — header `#Older (Alias),Younger (Alias)`:
  parenthesized headers naming field label + format.
- `test/data/person/marriages` — header
  `#Husband (ID)  Wife (ID)  Date`.

`Entity.add_identifiers(file, default, name, description)`
(`lib/scout/entity/identifiers.rb:84`) parses the file's
`all_fields` and registers **every** column as a known format of that
entity (`self.format = all_fields`), records the default/name formats, and
appends the file to `identifier_files`.

## 2. How files are located

Three ways (`lib/scout/tsv/attach.rb:228-253`):

1. **Explicit**: pass `identifiers:` to `TSV.open`, or a Path/TSV/Array to
   `translation_index`. KB/Association entity options do the same.
2. **Entity-declared**: `add_identifiers` on the entity module; the
   entity's `identifier_files` are used by `Entity::Identified#to` and by
   KnowledgeBase joins.
3. **Auto-discovery**: if a TSV's `filename` is a Path whose **sibling
   directory contains an entry named `identifiers`** (file or dir), that
   entry is used (`filename.dirname.identifiers`, `tsv/path.rb:14-21`,
   `tsv.rb:129-130`). There is **no** scan of `var/<namespace>/identifiers/`
   and **no** per-pair file naming: one file can serve many format pairs.

## 3. Header syntax: `Label (Format)`

A field header may be `Source Gene (Associated Gene Name)`: the label is
`Source Gene`, the format is `Associated Gene Name`. Matching
(`NamedArray.field_match`, scout-essentials `named_array.rb:10-20`) treats
such a header as matching **both** the request `Source Gene` (label) and
`Associated Gene Name` (format). `TSV.identify_field`
(`tsv/util.rb:47-50`) resolves field names this way, `:key` first.

When a parenthesized field is translated, the new header keeps the label
and swaps the format: `Source Gene (Associated Gene Name)` becomes
`Source Gene (Ensembl Gene ID)` (regex `(.*) \(.*\)` → `m[1] + "
(#{format})"`; `association.rb:56-78`, `translate.rb:123-127`).
A non-parenthesized key becomes just the target format name.

Probe P057s (repo fixture, executed): translating `marriages`
`Husband (ID)` → `Husband (Name)` yields key_field
`"Husband (Name)"`, fields unchanged `["Wife (ID)", "Date"]`, and the key
`"001"` becomes `"Miguel"`.

## 4. The translation pipeline

`TSV.translate(tsv, field, format)` (`tsv/change_id/translate.rb:116`):

1. Collect files: `tsv.identifier_files` plus any `identifiers:` argument
   (`translate.rb:118`) — **the data TSV itself participates** as the
   first file of the chain.
2. `TSV.translation_path(files, source, target)` (translate.rb:20-47)
   picks the chain: a single file containing both formats; else a pair of
   files sharing a common field; else a 3-file chain; else raises
   `Could not traverse identifier path from ... to ...`.
3. `TSV.translation_index(files, source, target)` (translate.rb:49-110)
   builds a lookup TSV `source → target`:
   - persisted (`Persist.persist(name, "HDB", ...)`), name
     `[source || "all", target] * "->" + " (N files - digest)"`;
   - first file of the chain is keyed on `source` (or `file.index target:`
     when source is nil); each later file is **attached**
     (`acc.attach file, insitu: false`), which re-keys through the shared
     field; the result is `slice([target]).to_single`.
4. The output TSV is rebuilt with new key/field names (Section 3) and the
   index applied to every row; `stream: true` returns a Transformer
   instead of materializing.

`TSV.change_key` / `TSV.change_id` (`tsv/change_id.rb`) are
attach-based wrappers: `change_key` attaches the identifier file and
re-keys when the new key field is not already a field of the source
(`change_id.rb:5-20`); `change_id` swaps one field
(`change_id.rb:30-40`).

## 5. Automatic use by attach

When the keys of two tables do not match, `attach` builds a translation
index from: explicit `identifiers:`, the source TSV itself, its
auto-discovered identifier files, the other TSV's identifier files, and
the other TSV itself (`attach.rb:79-87`). The join then proceeds through
the index. Probes P057t/P057u (executed):

- P057t: data keyed `Source Gene (Associated Gene Name)` + table keyed
  `Ensembl Gene ID` sharing field `Associated Gene Name` →
  `attach(fields: ["Ensembl Gene ID"])` returns rows keyed by the original
  names with the Ensembl column appended.
- P057u: no shared column at all; the sibling `identifiers` file
  (`#Associated Gene Name,Ensembl Gene ID`) bridges the join, and
  `translation_index([...], "Associated Gene Name", "Ensembl Gene ID")`
  maps `GENE1 → ENSG00000141510`.

## 6. Entities

`Entity::Identified` (entity/identifiers.rb) adds `to(format)`, `name`,
`default`. `to` builds `identifier_index(target, format)` =
`TSV.translation_index(identifier_files, format, target, persist: true)`
memoized in `Persist.memory`, then annotates results with the target
format (identifiers.rb:20-33, 63-70). `NAMESPACE` in a declared path is
substituted with the entity's `namespace` annotation; files with an
unresolved tag are rejected with a warning (identifiers.rb:48-59).

Probe P057a (executed): with the repo `person` identifiers,
`Person.setup("001", format: 'ID').to("Alias")` → `"Miki"`;
`to("Name")` → `"Miguel"`; arrays translate element-wise.

## 7. KnowledgeBase and Association

- KB entity setup: `annotate(entities, type)` uses
  `format = @format[type] || type` and `Entity.prepare_entity`, so the
  entity format is the association field's format unless `kb.format`
  overrides it (knowledge_base/entity.rb:36-40, entity.rb:24).
- `identify(db, source, target)` translates through the database's
  identifier files (`knowledge_base/traverse.rb:26`).
- Association with `source_format`/`target_format` builds
  `translation_index` over `[TSV.identifier_files(obj),
  Entity.identifier_files(format), identifiers]`, substitutes `[NAMESPACE]`
  from `options[:namespace]`, and rewrites parenthesized headers on both
  ends (association.rb:33-78).

## 8. Ecosystem attribution (verified in both repos)

Implemented in **scout-gear**:
`TSV.translation_path`, `TSV.translation_index`, `TSV.translate`,
`TSV.change_key/change_id`, `TSV#identifier_files` + sibling-directory
auto-discovery (`tsv/path.rb`), `Entity::Identified` (`to/name/default`),
`Entity.identifier_files`, `add_identifiers`, Association
header-rewriting, KB entity glue.

Provided by **scout-essentials** (dependency, verified source):
`NamedArray.field_match` / `identify_name` (`named_array.rb:10-20`),
`Path#method_missing` join (so `dirname.identifiers` works;
`path.rb:45-51`), `Persist` (HDB/memory), TSV core (`attach`, `index`,
`reorder`, `slice`, `to_single`, `parse_header`).

## 9. Downstream usage (relevance evidence only)

- Finances `lib/entity/security.rb:24`: `add_identifiers
  Scout.share.stocks.us.identifiers` — a single wide identifiers file.
- genomics `lib/rbbt/entity/gene.rb:13`: `add_identifiers
  Organism.identifiers("NAMESPACE"), "Ensembl Gene ID", "Associated Gene
  Name"` — one organism-wide multi-format identifiers file (Organism is
  provided by rbbt-sources, not scout-gear).
- AGS and SyntheticCancerGenome do not exercise this machinery.

## 10. Caveats / ambiguities (documented as such, not guaranteed)

- The persisted index name includes the file list and a digest of names,
  not file contents/mtimes; a changed identifier file does not
  automatically invalidate a cached index.
- `translation_path` supports chains of up to 3 files.
- Auto-discovery relies on `filename` being a `Path` with Path methods;
  plain-String filenames take a different branch (attach.rb:246-248).
