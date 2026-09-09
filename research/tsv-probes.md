# Investigation: TSV — Probe Findings

> **Non-normative.** This document is a working investigation with
> implementation details, code exploration notes, and hypotheses. Refer
> to `doc/user/` and `doc/developer/` for maintained documentation.

Consolidated record of the nineteen probes run against the TSV layer
(`lib/scout/tsv.rb` + `lib/scout/tsv/**`: parser, dumper, open, stream,
attach, index, traverse, transformer, change_id, translate, csv, path,
annotation, `util/*`). Each probe was executed through
`Observation/probe(<name>)` and its receipt cached; claim identifiers
below refer to the Cortex artifact `scout-gear/tsv.md` (map `current`),
which holds the full evidence chains. `lib/scout/tsv/.save/**` is a
legacy superseded copy and was excluded from the audit.

All probes ran in a plain Ruby environment, deterministic and
single-process, each standalone under `timeout 60`. The behaviors were
re-verified against HEAD `8a3a514` before promotion into
`doc/user/ProcessingTabularData.md`, `doc/user/Cookbook.md` and
`doc/developer/TSVInternals.md`.

---

## Summary of findings

1. **`sep2` defaults to `"|"` and only splits `:double` values.** The
   parser's own default (`TSV.parse_line`, `parser.rb:29`) is `"|"`; a
   `:list` value never splits on `sep2`. The internals doc previously
   said `","` (C1.3, C1.9).

2. **Name-based field/key selection needs a header; position works
   everywhere.** A `key_field`/`fields` String that matches nothing
   fails late with a bare `TypeError` from `Parser#traverse`
   (`parser.rb:47` `delete_at(nil)`) (C1.4, C1.7).

3. **`#:` header directives do not round-trip object-level options.**
   The directive parser is order-sensitive within a line (a
   `#: :sep=/t#:type=…` string becomes one value) and tolerant of the
   optional leading `:`; but a dump/reload cycle does not restore
   `entity_options` (or any other object-level option) — see the
   correction below (C1.8, C2.3).

4. **`TSV.open(TSV)` re-materializes.** Identity is lost, content and
   metadata survive; there is no `TSV.get` alias in scout-gear. An
   explicit `persist:` path serves old content after the source changes
   (C1.1, P031-adjacent `persist_files`).

5. **The two traverse APIs differ in `unnamed` default and return
   value.** The instance method yields `NamedArray` rows and returns
   `[key_field, fields]`; the class method defaults `unnamed: true` over
   raw streams, and with no `into:` discards block results (returning
   the empty parsed container for a stream source, the header pair for a
   TSV/Parser source). With `into:` the target itself is returned
   (`into || res`, `open.rb:202`) (C3.1, C3.2, C3.3).

6. **`into: :tsv` and friends are not targets.** A Symbol falls through
   the `traverse_add` `case` untouched; nothing is collected and the
   symbol comes back unchanged. `into: :stream` is the one special-cased
   symbol (C3.2/P031f, `open.rb:38-44`).

7. **Parallel callback/into arrival order is not contractual.** Under
   `cpus:` the callback receives results in completion order — trials
   flip between ordered and unordered for the same input. Block
   exceptions abort the WorkQueue and re-raise at the call site (C3.4,
   C3.6).

8. **`into:` semantics per target type.** A `:double` TSV target merges
   via `zip_new`; other TSV types are last-wins; `Array`/`Set` append
   whole `[key, values]` pairs; `IO`/`StringIO` gets one `puts` per
   result; a `Path` is written with `Open.write` (C3.5, C3.7).

9. **`Dumper` writes its header lazily at first `add`.** The write API
   is exactly `add`/`close`/`abort` (no `add_row`); `close` without any
   `add` yields empty output and EOF — the header is never written
   (C4.1).

10. **`dumper_stream` is the serializer behind `to_s`.** `#stream` is an
    alias; `unmerge: true` splits `|`-joined `:double` sub-values into
    one row each, `keys:` subsets, `preamble: false` drops the `#:`
    line (C4.2, C4.5).

11. **`paste_streams` aligns on the first stream's key order and pads
    missing keys with empty columns; `collapse_stream` merges only
    *consecutive* duplicate keys.** Neither takes a `bar:` keyword
    (ArgumentError) (C4.3, C4.4).

12. **`Transformer` semantics.** `#traverse` pipes into the dumper and
    returns the stream; forgetting the `traverse` call leaves the dumper
    un-fed and `.tsv` would block on the pipe. A String argument to
    `Transformer.new` is a *filename* (`Errno::ENOENT`); block arity
    follows the source type, not the target's; a TSV target is populated
    in place (same object), a `Dumper` target exposes `.stream` (C5.1,
    C5.2, C5.3, C5.4).

13. **In-memory `attach` mutates and returns the receiver.** Missing
    matches leave `nil`/empty entries silently; `complete: true` adds
    rows for keys present only on the other side; `identifiers:`
    auto-bridges key formats while keeping the target's key field. The
    keyword is `match_key:` (there is no `field:`), and
    `TSV::Parser#attach` does not exist. Streaming attach
    (`target: :stream`) returns a `TSV::Transformer`; a plain TSV target
    in that path raises `TypeError` (C6.1–C6.6).

14. **`TSV.index` defaults to indexing *every* column.** With
    `fields: :all` (the default) every distinct value in any column
    becomes an index key mapping to the target value; the index's
    `key_field` is the comma-joined list of *all* indexed column names
    and its single field is the target. First row seen wins for both
    `order:` settings. `persist: true` returns a `TokyoCabinet::HDB`
    instead of a Hash (C7.1–C7.6).

15. **`translation_index` persists *by default*** (HDB under
    `~/.scout/var/cache/persistence`, basename
    `Translation_index:<source>-><target>_(N_files_-_md5)`), unlike
    `TSV.index`. Chains match on column *names* in either order;
    untranslated rows survive with an empty-string key, which silently
    merges them (C8.1, C8.2, C8.3).

16. **`TSV.csv` exists, `TSV::CSV` does not.** `headers: false` keys
    rows `row-0`, `row-1`, …; `fields:` forces a `:double` intermediate
    rebuild. `TSV.setup` also accepts a `"Key~F1,F2#:type=:list"` DSL
    string; `lib/scout/tsv/path.rb` *extends* `Path` (there is no
    `TSV::Path`), and `#:` subpaths are a Parser concern, not a Path
    feature (C10.1, C10.2, C10.3).

17. **Util layer signatures.** `melt_columns(value_field, column_field)`
    is positional, keys become `"<key>:<index>"`; `filter` match strings
    must be `:key` or `field:<name>`; `sort_by` returns an Array of
    `[key, values]` pairs; `process` mutates in place and returns the
    receiver; `slice` projects fields; `unzip` resolves its field by
    name (composite key fields like `ID:A` are not searched) and on a
    `Parser` returns a `Transformer`; `reorder` defaults `merge: true`
    and re-keys with the remaining columns as fields (C9.1–C9.8).

---

## Probe ledger

### `tsv_annotation_rows`

Probed row annotation: what `[]`/`each` return per value type, the
effect of `with_unnamed`, and which metadata survives a dump/reload.

Finding: `:list`/`:double` rows are `NamedArray`-annotated (`fields` +
`key`); `:single` rows are Strings, `:flat` rows plain arrays;
`to_hash` is an unannotated Hash. `with_unnamed` strips the annotation
inside the block and restores it after.

*Correction (re-verification at HEAD `8a3a514`):* neither `entity_options`
nor the `unnamed` flag survives a dump/reload cycle. The preamble writer
(`Dumper.header` → `IndiferentHash.hash2string`) only emits Scalar-valued
options, so a Hash-valued `entity_options` is dropped; and the reader does
not map a `#:entity_options=` directive back into the option. The probe's
original note reported a round-trip that live code does not provide; the
promoted docs state the verified direction (not preserved).

- Receipt: `Observation/probe/tsv_annotation_rows_80e1c8d0eff758170081fdce90645d33.json`
- Claims: C2.1, C2.2, C2.3

### `tsv_attach_semantics`

Probed `TSV#attach` join semantics: by key, by `match_key:`, via
`identifiers:`, with `fields:` subsetting and `complete:`.

Finding: attach on an in-memory TSV mutates and returns the receiver,
accumulating columns across calls; missing keys yield `nil`/empty
entries with no error; `match_key:` (not `field:`) selects a target
column; `identifiers:` translates mismatched key formats while keeping
the target's key field; `complete: true` adds rows for keys present
only in the source.

- Receipt: `Observation/probe/tsv_attach_semantics_21a75f35a1bc96ef29eac768557b3fe4.json`
- Claims: C6.1, C6.2, C6.3, C6.5, C6.6

### `tsv_attach_target`

Probed the streaming attach path (`TSV.attach(file, file, …)`) and
target-object dispatch.

Finding: `target: :stream` returns a `TSV::Transformer` whose `.tsv`
materializes with the first file's key field and merged fields; a plain
`TSV`/Hash target in the streaming path raises `TypeError: no implicit
conversion of nil into Array`; `fields:` subsetting works; `complete:`
grows the key set; `TSV::Parser#attach` does not exist
(NoMethodError).

- Receipt: `Observation/probe/tsv_attach_target_1a73c081a72b1d9be4dda96cd44b0c2a.json`
- Claims: C6.1, C6.2, C6.4, C6.6

### `tsv_change_id_translate`

Probed identifier translation end to end: `translate`'s strict
name-matching, the fate of untranslated rows, `change_key`'s two entry
points, and `key_field:` validation.

Finding: format names must match column names literally or
`Could not traverse identifier path from X to Y` raises; untranslated
rows survive with an empty-string key; the *string* entry point
`TSV.change_key(filename, …)` is broken (ArgumentError from a stale
1-arg `Parser#identify_field`), the *instance* `TSV#change_key` works;
`change_key(stream: true)` returns a Transformer; `key_field:` naming a
missing column fails with a bare `TypeError` at `parser.rb:47`.

- Receipt: `Observation/probe/tsv_change_id_translate_fdafb76c464ed95d7b9db869cd94b451.json`
- Claims: C1.7, C8.3, C8.4, C8.5

### `tsv_csv_and_setup_strings`

Probed `TSV.csv` and the string forms accepted by `TSV.setup`, plus the
`Path` integration in `lib/scout/tsv/path.rb`.

Finding: `TSV.csv` exists with built-in defaults (`headers: true`,
`type: :list`) and there is no `TSV::CSV` constant; `headers: false`
keys rows `row-0`, `row-1`, …; `fields:` forces a `:double`
intermediate. `TSV.setup({}, "Key~F1,F2#:type=:list")` is the DSL form
(`~` splits key from fields; a bare key gives empty fields).
`lib/scout/tsv/path.rb` extends `Path` (`Path#tsv`, `#tsv_options`,
`#index`); `Path.setup(f + "#:field=V1")` stays literal and `.find`
fails ENOENT.

- Receipt: `Observation/probe/tsv_csv_and_setup_strings_691fba461838a94e38b6b5b3b20424f0.json`
- Claims: C10.1, C10.2, C10.3

### `tsv_dumper_lifecycle`

Probed `TSV::Dumper` producer/consumer lifecycle and its write API.

Finding: the header is written lazily at the first `add`
(`initialized?` false → true); the write API is exactly
`add`/`close`/`abort` (no `add_row`); a reader on `dumper.stream`
blocks until `close`, and `close` with no `add` produces empty output —
the header is never written.

- Receipt: `Observation/probe/tsv_dumper_lifecycle_94dba76ba3ed9a3fd29f2106be261298.json`
- Claims: C4.1

### `tsv_dumper_stream`

Probed `TSV#dumper_stream` and its options.

Finding: emits the `#:` directive plus rows; `unmerge: true` splits
`|`-joined sub-values into one row each; `keys:` restricts the row set;
`preamble: false` drops the directive line entirely; `#to_s` is the
stream read to EOF.

- Receipt: `Observation/probe/tsv_dumper_stream_0d9acf360a8604a3ea7716d0435ce86f.json`
- Claims: C4.2

### `tsv_index`

Probed the basic `TSV.index` build (`target:`/`fields:`/`persist:`).

Finding: with default `fields: :all` the index answers for the values of
every column, not just the target; persisting changes the returned object
class and caches beside the source file.

- Receipt: `Observation/probe/tsv_index_9f0fd717d4202d63f59df80626fee6a7.json`
- Claims: C7.1, C7.4

### `tsv_index_semantics`

Probed the full `TSV.index`/`#index`/`range_index` surface.

Finding: the default build indexes every column and maps each value to
the target (`target: :key` → the row key); the index `key_field` is all
indexed column names comma-joined and `fields` is the target name;
duplicate source values resolve first-row-seen-wins under both `order:`
settings; `persist: true` yields `TokyoCabinet::HDB` and a second call
hits the cache; `range_index` returns a `FixWidthTable` whose `[]`
takes a coordinate and lists covering keys; the instance method
defaults `target: :key`.

- Receipt: `Observation/probe/tsv_index_semantics_d69f4ad4c61069edb4e1411b6a6f985b.json`
- Claims: C7.1, C7.2, C7.3, C7.4, C7.5, C7.6

### `tsv_open_entrypoints`

Probed `TSV.open` option semantics and dispatch.

Finding: `TSV.open(tsv)` returns a re-materialized copy, not the same
object; `key_field`/`fields` accept name (String/Symbol), position, and
`:key`, with the key column dropped from `fields:` when it matches a
header name and not re-requested; `cast:` applies per value with the key
staying a String; `select:` filters at open; `TSV.get` does not exist;
an explicit `persist:` path serves old content after the source changes;
open options override `#:` directives; `header_hash` accepts any marker
string.

- Receipt: `Observation/probe/tsv_open_entrypoints_9c84731be377c650e7fc1936dd402c77.json`
- Claims: C1.1, C1.2, C1.4, C1.5, C1.6

### `tsv_parser_header_directives`

Probed `#:` directive parsing: tail tolerance, `sep2`, `header_hash`
values, and headerless field selection.

Finding: `#: :type=:double` and `#:type=:double` parse alike; a
value-less directive yields a boolean; `sep2` is available both as a
directive and an open option; `header_hash: ""` behaves like `true`
while `false`/`none`/`~` disable headers entirely (keys become the raw
first line, `key_field: nil`); named field selection without a header
raises `Non-numeric fields specified`.

- Receipt: `Observation/probe/tsv_parser_header_directives_2fac199c8b5b367c39c3d6d72d566236.json`
- Claims: C1.2, C1.3, C1.4, C1.8

### `tsv_parser_sep2_default`

Probed the actual default value of `sep2` and which types it applies to.

Finding: `TSV.parse_line` declares `sep2: "|"`; `"x|y"` splits to
`["x","y"]` in a `:double` TSV while `"x,y"` stays one value; a `:list`
TSV never splits values on `sep2`; overriding with `sep2: ":"` works; a
`:flat` key `"a|b"` is not split in the tested fixture.

- Receipt: `Observation/probe/tsv_parser_sep2_default_a38c021445a74c0ccb0149a816603ad4.json`
- Claims: C1.3, C1.9

### `tsv_stream_pipeline`

Probed `paste_streams`, `collapse_stream`, and the stream-shaped TSV
entry points.

Finding: `paste_streams` emits `#: :compact=false#:type=:double` and
aligns on the first stream's key order, padding a key missing on one
side with empty trailing columns; it accepts TSV instances (using their
`dumper_stream`) and takes no `bar:` keyword; `#to_s` equals
`dumper_stream`, `#stream` is its alias, `write_file` materializes the
same text; `collapse_stream` folds duplicate keys into `|`-joined values
and emits a plain `#ID` header; `TSV.open(..., stream: true)` returns an
IO-backed stream that can be traversed without materializing.

- Receipt: `Observation/probe/tsv_stream_pipeline_01a787ca0fc21dd87098dc9261d59c08.json`
- Claims: C4.3, C4.4, C4.5

### `tsv_transformer_semantics`

Probed `TSV::Transformer` construction, source handling, `#traverse`,
`.tsv` materialization, and target objects.

Finding: `Transformer#traverse` sets `into: @dumper` and returns the
stream; omitting it leaves the dumper un-fed and would block `.tsv` on
the pipe; a String source is a *filename* (`Errno::ENOENT`); block arity
follows the source type (a `:double` source yields nested arrays); a TSV
target is populated in place (same object) and a `Dumper` target exposes
`.stream`.

- Receipt: `Observation/probe/tsv_transformer_semantics_b116e618e1eb76b6520bb742e115cb03.json`
- Claims: C5.1, C5.2, C5.3, C5.4

### `tsv_translation_index`

Probed `TSV.translation_index` / `translation_path`.

Finding: chains match on column *names* in either order and chaining
across two files works; the index is persisted by default (HDB) under
`~/.scout/var/cache/persistence` with a
`Translation_index:<source>-><target>_(N_files_-_md5)` basename and a
second call returns the cached object; no path raises a descriptive
`RuntimeError` embedding the source TSV fingerprint; many-to-one
mappings collapse to one value.

- Receipt: `Observation/probe/tsv_translation_index_d1d695c487b0e280fa2434295dd3e695.json`
- Claims: C8.1, C8.2, C8.3

### `tsv_traverse_apis`

Probed the instance and class traverse APIs side by side.

Finding: the instance method yields `NamedArray` rows by default and
returns `[key_name, field_names]`; the class method defaults
`unnamed: true` for raw streams but honors a TSV instance's own setting;
a 3-arity block receives `nil` as the third element; multi-key rows join
with `|` by default and cannot be selected by named fields;
`one2one: :strict` validates exactly one element per field; traversing
with a different `type:` coerces the value to the *requested* type.

- Receipt: `Observation/probe/tsv_traverse_apis_57949f3dbfd63c7bf327083954c75de2.json`
- Claims: C3.1, C3.8, C3.9

### `tsv_traverse_parallel_ordering`

Probed `TSV.traverse` parallelism, ordering guarantees, and `into:`
target semantics.

Finding: with `cpus: 4` the callback arrival order flips between
ordered and unordered across runs for the same input; sequential
traversal is always source-ordered; `into:` returns the target itself;
an `into:` Array holds `[k, v]` pairs (and `MultipleResult` fans an
Array of results into separate `traverse_add` calls); a block exception
propagates at the call site after the queue aborts; without `into:` the
return is the empty parsed container (stream source) with results
discarded; `into:` a `:double` TSV merges via `zip_new` while other
types are last-wins.

- Receipt: `Observation/probe/tsv_traverse_parallel_ordering_9cbf35b79b11e7685920edfc87b9d7d3.json`
- Claims: C3.2, C3.3, C3.4, C3.5, C3.6, C3.7

### `tsv_util_matrix`

Probed the util layer: `process`, `unzip`, `melt_columns`, `select`,
`filter`, `reorder`, `sort`, `slice`.

Finding: `process` mutates in place and returns the receiver; `unzip`
resolves its field by name, joins new keys with `sep`, and on a `Parser`
returns a `Transformer` backed by an IO stream; `melt_columns` keys
become `"<key>:<index>"` with fields
`[key_field, value_field, column_field]`; `select` accepts Hash/Regexp/
block with no field projection; `reorder` defaults `merge: true` and
keeps the remaining columns as fields; `slice` projects fields in place.

- Receipt: `Observation/probe/tsv_util_matrix_b86ef5f8b78a5cdd331226e0fa2e2be1.json`
- Claims: C9.1, C9.4, C9.5, C9.6, C9.7, C9.8

### `tsv_util_small_tools`

Probed the remaining `util/*` entry points: `melt`, `filter` match
syntax, `select` variants, `sort_by`, `process`, `unzip`.

Finding: `melt_columns(value_field, column_field)` is positional with no
options; filter match strings must be `:key` or `field:<name>` (anything
else raises `Unknown match`), filters intersect and `pop_filter`
restores; `filter` works without a `filename` but `filtered_filename`
(persistence) needs one; `sort_by` returns an Array of `[key, value]`
pairs; `process` mutates and returns the receiver; `select` with a Hash
is a `field => values` spec.

- Receipt: `Observation/probe/tsv_util_small_tools_ff70c0c8f7aa0aa77888873737e7b9ca.json`
- Claims: C9.1, C9.2, C9.3, C9.4, C9.5

---

## Improvement candidates (defects, not documented as normal behavior)

- The **string** entry point `TSV.change_key(filename, …)` is broken:
  `change_id.rb:7` wraps the string in `TSV::Parser` and calls
  `identify_field` with `strict: true`, but `Parser#identify_field`
  (`parser.rb:375`) still takes a single positional argument —
  `ArgumentError: wrong number of arguments (given 2, expected 1)`. The
  instance method `TSV#change_key` (in `util.rb`, `strict: nil`) works.
  Claim 8.4.
- A plain `TSV`/Hash target in the *streaming* attach path
  (`TSV.attach(file, file, target: <tsv>)`) raises
  `TypeError: no implicit conversion of nil into Array` instead of a
  useful error. Claim 6.4.
- `TSV.open(..., key_field: <name not in header>)` fails with a bare
  `TypeError: no implicit conversion from nil to integer`
  (`parser.rb:47`, `delete_at(nil)`) rather than a named-field
  validation error. Claim 1.7.
- `unzip(field)` on a TSV whose key field is composite (`"ID:A"`) raises
  `TypeError` because the field is only resolved against the *fields*
  list, never against the key field. Claim 9.7.
- `TSV.paste_streams` rejects `bar:` with `ArgumentError` while every
  neighbouring entry point accepts it. Claim 4.3 (adjacent).

These belong in `Improvements.md`, not in the user/developer docs.

---


## Consolidation audit (2026-09-09, HEAD 8a3a514)

- Receipt cross-check: all 19 `- Receipt:` citations resolve to a
  `property_job` in the matching registry record under
  `var/cortex/properties/Observation/probe/` (the registry stores one
  JSON per probe; the `_hash` suffix in the citation is the job
  fingerprint, not a separate file).
- Claim coverage: the 58 claim ids in this ledger are identical to the
  58 `### Claim N.N` headers of the claims artifact
  `scout-gear/tsv.md`.
- Spot re-verification at HEAD (inline probes, not persisted): C1.4
  (headerless name selection raises `Non-numeric fields specified`),
  C1.7 (absent key_field name → `TypeError: no implicit conversion from
  nil to integer`), C7.1 (`index.key_field` is the comma-joined column
  list), C9.6 (`slice` returns a new TSV, receiver untouched), C10.2
  (`TSV.setup({}, "Key~F1,F2#:type=:list")` DSL string), C10.3
  (`Path#tsv` forwards options). All reproduced.
## Round-trip caveats re-verified at promotion time

Two dump/reload caveats surfaced while promoting the probe findings into
`doc/` and are recorded here because they qualify the claims above:

- **`sep2` is a read-side option.** `dumper_stream` rejoins `:double`
  sub-values with a literal `"|"` no matter which `sep2` the TSV was
  opened with, and no `#: :sep2=` directive is written into the preamble.
  Reopening such a dump with the default `sep2` therefore re-splits on
  `|` and yields a single-element sub-array per value. Redeclaring
  `sep2:` at open still works, but a bare `:` in the directive is read
  back as a Symbol (`TypeError`); quote the value (`#: :sep2=':'`) or use
  a multi-character separator.
- **`entity_options` does not round-trip.** See the correction under
  `tsv_annotation_rows` above.

## Deliberately left open

- **WorkQueue internals under `cpus:`** — fork/IPC mechanics live in
  scout-essentials; probed only at the TSV interface (ordering, error
  propagation).
- **`FixWidthTable` internals** — `range_index` returns one, but the
  table's own API belongs to scout-essentials; only `[]`-lookup was
  probed.
- **`.save` legacy tree** — excluded per campaign scope.
- **`TSV::Serializer`/`TSVAdapter` persistence details** — owned by the
  Persist agent (`scout-gear/persistence-engines.md` in the same
  workspace); TSV probes touch persistence only through `persist:`
  options.
- **`TSV.traverse` `keep_open:` / bar interplay** — visible in code
  (`open.rb:36`) but not load-bearing for the claims; left for a
  follow-up if a use case appears.
- **`#:`-subpath syntax on `Path` objects** — works inside
  `TSV::Parser` option strings but is not a Path feature; no in-repo
  code constructs such Paths programmatically.
