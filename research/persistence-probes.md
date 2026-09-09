# Investigation: Persistence Engines — Probe Findings

> **Non-normative.** This document is a working investigation with
> implementation details, code exploration notes, and hypotheses. Refer
> to `doc/developer/` for maintained architectural documentation.

Consolidated record of the eleven probes run against the persistence
engine layer (`lib/scout/persist/**`, scout-gear) during the
documentation-consolidation campaign. Each probe was executed through
`Observation/probe(<name>)` and its receipt cached; claim identifiers
below refer to the Cortex artifact `scout-gear/persistence-engines.md`
(map `current`), which holds the full evidence chains.

All probes ran in a plain Ruby environment with the `tokyocabinet` gem
available and the `tkrzw` gem absent (bwrap sandbox, no forks, no
sleeps), each standalone under `timeout 60`. The behaviors were
re-verified against HEAD `8a3a514` before promotion into
`doc/developer/PersistenceEngines.md` and `doc/user/CachingData.md`.

## Summary of findings

1. **Engine dispatch is narrow and String-typed.** `Persist.open_database`
   has two String case arms (`'fwt'`, `'pki'`) plus a TokyoCabinet
   fallback. Accepted engine names: `"HDB"`, `"BDB"` (and `:HDB`/`:BDB`
   Symbols), `":big"`-suffixed variants, `"fwt"`, `"pki"`. Everything
   else — `"tkrzw"`, `:fwt`, `"sharder"` — fails with
   `NoMethodError: undefined method 'new' for an instance of String`.
   *(C1)*
2. **The engine is not part of cache identity.** `persistence_path` is
   identical across `"HDB"`/`"BDB"`/`"fwt"` for a given identifier;
   identity is identifier + `:other`-namespaced options. Neither is the
   block body: a second `Persist.tsv` with the same id serves the first
   call's data without running its block. *(C2, C10)*
3. **Serializer attachment is conditional.** A default serializer is only
   attached when the extended object is already a `TSV`; a bare
   `Persist.open_database(path, true)` result has `serializer == nil`
   and `[]=` fails on Ruby structures. Serialize through
   `persist_options[:serializer]`, or populate via `TSV.open(source,
   data: db, …)` / `TSV.setup`. *(C3)*
4. **`close` is advisory.** TokyoCabinet `close` marks the object closed
   but leaves it in `Persist::CONNECTIONS`, which is never invalidated;
   a subsequent open of the same path returns the *closed* object. That
   object is not inert: writes through it still reach the file (verified
   by copying the database and reading it back), so the exposure is a
   stale *read* view, not lost writes. FixWidthTable data is on disk
   after close and reloads fine; Sharder close delegates to shards.
   *(C5)*
5. **The Sharder is not self-describing.** Its directory (`shard-*` +
   `metadata`) does not persist the shard function; a raw `open_sharder`
   reopen yields `shard_function == nil` and `[]` raises `NoMethodError`.
   *(C6)*
6. **FixWidthTable is not a TSVAdapter.** No `key_field`/`fields`, no
   `keys`/`each`; positions must be Integer, `Range`, or `[start, end]`.
   A String position is not parsed and wedges the binary search. *(C7)*
7. **PackedIndex masks fail late and there is no `:pki` load driver.**
   Unknown/bare codes produce `item_size < 3` then
   `ArgumentError: negative argument`. `Persist.load(path, :pki)` raises
   `RuntimeError: Persist does not know :pki` (the essentials
   `deserialize` fallback — it never attempts to reopen the file);
   reopening works with `Persist.open_pki(path, false, nil)`, which reads
   the mask back from the 8-byte file header, provided the
   `pos_function` is passed again as a block (it is not persisted; a
   String key lookup without it raises `TypeError`). *(C8)*
8. **Three distinct outcomes when reopening a TSV database.**
   `Persist.load(path, :HDB)` works; bare `TSV.open(path)` text-parses
   into a near-empty `Hash`; `TSV.open(path, persist: true)` keys on
   `TSV:<abs path>` and builds a *fresh* database whose keys are the
   annotation blob written as data (binary garbage). *(C9)*
9. **Load-time availability degrades silently.** A missing
   `tokyocabinet` gem only logs a warning at require time; the failure
   surfaces at first use. tkrzw is neither required nor installed, and
   registers no `:tkh` drivers in a standard load. *(C11)*

## Probe ledger

### `persist_engine_selection`

- **Probed**: what `Persist.open_database` accepts and how unknown engine
  names fail.
- **Finding**: exactly two String case arms plus a TokyoCabinet fallback;
  `"HDB"`/`:HDB`/`"BDB"`/`:BDB`/`:big` are normalized in
  `ScoutCabinet.open`; anything else is used as a class name and raises
  `NoMethodError`. Same identifier yields the same path for every engine.
- **Receipt**: `Observation/probe/persist_engine_selection_f58f907313845edc7e5bb649d55dc2e6.json`
- **Claims**: C1, C2

### `persist_serializer_fidelity`

- **Probed**: the `TSVAdapter::SERIALIZER_ALIAS` table and when a default
  serializer is attached.
- **Finding**: 17 alias keys; the default is attached **only** when the
  extended object is already a `TSV` at `TSVAdapter.extended(base)` time,
  which is why a bare `open_database` object raises
  `no implicit conversion of Array into String` on `[]=`.
- **Receipt**: `Observation/probe/persist_serializer_fidelity_5de96084da9d846cb3ae242157a080b8.json`
- **Claims**: C3

### `persist_tsv_adapter_annotations`

- **Probed**: which TSV annotations survive close/reopen, and object
  identity across repeated `Persist.tsv` calls.
- **Finding**: `key_field`/fields/type/namespace round-trip through the
  marshalled `__annotation_hash__` sentinel key; `keys`/`size` discount
  it; a second `Persist.tsv` for the same id returns the same object
  (`persist_options[:data]` + `Persist::CONNECTIONS`).
- **Receipt**: `Observation/probe/persist_tsv_adapter_annotations_853d4c11ad45545f4c3953bd87489fbb.json`
- **Claims**: C4

### `persist_adapter_matrix`

- **Probed**: side-by-side matrix of the adapter surfaces (HDB, FWT,
  PKI, Sharder).
- **Finding**: FWT and PKI are **not** TSVAdapters (no TSV surface);
  Sharder reopen loses `shard_function` and raises `NoMethodError` on
  `[]`.
- **Receipt**: `Observation/probe/persist_adapter_matrix_531d4e97b1f8de37c0c190ddb0c0160a.json`
- **Claims**: C6, C7

### `persist_engine_lifetime`

- **Probed**: `close` semantics per engine.
- **Finding**: TokyoCabinet `close` closes the native handle but the
  object stays in `Persist::CONNECTIONS` and is returned by later opens
  of the same path; FWT reloads from disk; Sharder `close` delegates to
  shards.
- **Receipt**: `Observation/probe/persist_engine_lifetime_a83c1d3350ce1bdbc04cc95d62ff1f70.json`
- **Claims**: C5

### `persist_tsv_open_roundtrip`

- **Probed**: reopening a TSV written by `Persist.tsv` through the three
  plausible entry points.
- **Finding**: `Persist.load(file, :HDB)` works; bare `TSV.open(file)`
  text-parses into a plain `Hash` (`k1 == nil`);
  `TSV.open(path, persist: true)` keys on `TSV:<abs path>`, builds a
  fresh database, and `keys` shows binary garbage from the annotation
  blob written as data.
- **Receipt**: `Observation/probe/persist_tsv_open_roundtrip_4d717a6d83ac4d3a9aebab5c0c2d3299.json`
- **Claims**: C9, C12 (#2)

### `persist_cache_identity`

- **Probed**: what participates in the cache identity.
- **Finding**: the engine string does not (`HDB`/`BDB`/`fwt` share a
  path); neither does the block body — a second `Persist.tsv` call with a
  different block serves the first call's data.
- **Receipt**: `Observation/probe/persist_cache_identity_204e3163af8d74ea0c93b848b54894b2.json`
- **Claims**: C2, C10, C12 (#3)

### `persist_loader_and_availability`

- **Probed**: the require graph, gem availability, and registered
  drivers.
- **Finding**: `persist/engine.rb` and `tsv/adapter.rb` never require
  tkrzw; after `require 'scout'` the drivers are `:HDB`, `:BDB`, `:fwt`,
  `:tsv` (plus essentials' `:chat`) — no `:tkh`, no `:pki`.
- **Receipt**: `Observation/probe/persist_loader_and_availability_7fe10205065dbf56c91172b820a2c00e.json`
- **Claims**: C11, C8

### `persist_fwt_pki_surface`

- **Probed**: the FWT query surface and the PackedIndex mask grammar.
- **Finding**: FWT exposes `[]`/`range`/`overlaps`/`get_range` with
  Integer/`Range`/`[start, end]` positions only — a String position is
  not parsed and hangs the binary search. PKI masks must be String
  arrays; unknown codes raise `ArgumentError: negative argument`
  indirectly, and reopening a written index fails because no `:pki`
  load driver exists.
- **Receipt**: `Observation/probe/persist_fwt_pki_surface_7309a411094733c9eb924483055f5f81.json`
- **Claims**: C7, C8, C12 (#6)

### `persist_tsv_block_contract`

- **Probed**: the `Persist.tsv` keyword contract and block/data reuse.
- **Finding**: the signature is `(id, options, engine:, persist_options:)`
  — `serializer:` must go inside `persist_options` or it raises
  `unknown keyword`; `persist_options[:data]` is reused across calls for
  the same id.
- **Receipt**: `Observation/probe/persist_tsv_block_contract_f7019c613b1d9c7fdccf052a9618e887.json`
- **Claims**: C3, C4, C12 (#7)

### `persist_doc_code_discrepancies`

- **Probed**: doc/code divergence, statically and by execution.
- **Finding**: seven discrepancies, including `"sharder"` listed as an
  `open_database` type (it is not reachable that way), "TSV.open detects
  an existing database" (only with `persist: true` on a source file),
  and cache identity overstating the engine's role.
- **Receipt**: `Observation/probe/persist_doc_code_discrepancies_93cf7bf260e5cccd6d5bb3e1c6146114.json`
- **Claims**: C1, C11, C12

## Corrections to earlier research notes

`research/persistence-concurrency-analysis.md` (non-normative, kept as a
point-in-time investigation) contains three statements that the probes
supersede:

- Its engine table lists `"sharder"` as an `open_database` type. There is
  no such case arm; the Sharder is built by `Persist.tsv` through
  `Persist.open_sharder` when `persist_options[:shard_function]` is
  given.
- Its serializer table marks the integer/float nil sentinels "N/A". The
  *array* serializers do carry sentinels (`IntegerArraySerializer::NIL_INT
  = -999`, `FloatArraySerializer::NIL_FLOAT = -999.999`); the scalar
  `:integer`/`:float` serializers do not, and 17 alias keys exist.
- Its "Lock files are stored in `tmp/tsv_locks/`" statement refers to the
  relative default (`TSVAdapter.lock_dir`, `persist/tsv/adapter/base.rb`);
  resolved it lands under `~/.scout/tmp/tsv_locks`, while
  `Persist.lock_dir` (scout-essentials, used by `Persist.persist`) is
  `~/.scout/tmp/persist_locks`. Note that `Sharder#write_and_close` /
  `#write_and_read` call `TSV.lock_dir`, which does not exist on the
  `TSV` module — see the improvement candidates below.

## Improvement candidates (defects, not documented as normal behavior)

1. `Sharder#write_and_read`/`write_and_close` call `TSV.lock_dir`
   (`lib/scout/persist/engine/sharder.rb:129,144`), but `lock_dir` is
   defined on `TSVAdapter`, not on `TSV` — both methods raise
   `NoMethodError` when reached.
2. `TSV.open(db_path, persist: true)` on a *database* path silently
   builds a fresh database keyed `TSV:<abs path>` and writes the
   annotation blob as data, yielding binary-garbage keys instead of an
   error.
3. No `:pki` entry in `load_drivers`: `Persist.load(path, :pki)` raises
   `RuntimeError: Persist does not know :pki` instead of reopening (the
   index is self-describing on disk — the mask is in its header — so a
   load driver could reopen without the pattern).
4. PackedIndex mask parsing accepts unknown/bare codes and fails later
   with `ArgumentError: negative argument` from `initialize`; a parse-time
   validation error would be far cheaper to diagnose.
5. `Persist::CONNECTIONS` is never invalidated by `close`, so a closed
   database object is silently handed back by later opens of the same
   path. Writes through it still reach disk, but reads served by it do
   not reflect other handles, and the `@closed`/`@writable` flags are not
   observable as a coherent state.
6. Engine availability is probed at load time with only a
   `Log.warn`; a missing `tokyocabinet` gem surfaces as a
   `NameError`/`NoMethodError` at first use rather than at startup, and
   there is no queryable availability API.
7. The engine string is not part of the persistence path, so switching
   engines for an existing identifier reuses the previously written file
   (a format mismatch surfaces as a TokyoCabinet open error, if at all).

## Consolidation audit (2026-09-09, HEAD 8a3a514)

Spot re-verification of the highest-impact claims at HEAD, run as fresh
standalone snippets under `timeout 120` (plain `require "scout"` /
`"scout/tsv"`, tokyocabinet present, tkrzw absent):

- **C1 / C2 (engine dispatch + cache identity)** — confirmed. Unknown
  names (`"tkrzw"`, `:fwt`) raise
  `NoMethodError: undefined method 'new' for an instance of String`;
  `"HDB:big"` is accepted; `persistence_path` is identical across
  `"HDB"`/`"BDB"`/`"fwt"` for the same identifier.
- **C5 (close / CONNECTIONS)** — confirmed, with one correction recorded
  below. Reopening the same path after `close` returns the same
  (closed-flagged) object (`db.equal?(reopened) == true`). The probe-era
  wording "not backed by a live handle" overstated the damage: writes
  through the cached closed object **do** reach disk (verified by copying
  the file and reading the copy: the new key is present). The residual
  defect is a stale read view, not lost writes.
- **C6 (Sharder reopen)** — confirmed on both paths: `Sharder#[]` after a
  bare reopen raises `NoMethodError: undefined method 'call' for nil`, and
  the *raw* engine's `write_and_read`/`write_and_close` raise
  `NoMethodError: undefined method 'lock_dir' for module TSV`. The
  adapter-level `write_and_read` (which mixes in `TSVAdapter`) works, so
  the defect only bites consumers of the raw `Sharder`.
- **C8 (PackedIndex mask + no `:pki` load driver)** — confirmed with a
  corrected error signature: `Persist.load(path, :pki)` raises
  `RuntimeError: Persist does not know :pki` (the essentials
  `deserialize` fallback), *not* the `TypeError` the probe ledger
  originally recorded; the `TypeError` appears only when a reopened
  `PackedIndex` is indexed by a String key without a `pos_function`.
  New positive finding: `Persist.open_pki(path, false, nil)` reopens
  correctly — the mask is read back from the file header — so the
  `:pki` load driver gap is a wiring omission, not a format limitation.
- **C9 (three reopen outcomes)** — confirmed:
  `Persist.load(file, :HDB)` returns the annotated database;
  bare `TSV.open(db_path)` returns a plain `Hash` with `k1 == nil`;
  `TSV.open(db_path, persist: true)` returns a fresh TokyoCabinet
  database whose `keys` are binary garbage (the annotation blob written
  as data).
- **C10 (block body not part of identity)** — confirmed: a second
  `Persist.tsv` with the same id and a different block does not run the
  block (`id2 == nil`) and serves `id1`'s data.
- **HDB save driver contract (feeds C1/C12)** — refined: a block that
  returns a plain `Hash` fails *at save time* with
  `NoMethodError: undefined method 'annotate' for an instance of Hash`
  (it does not silently re-run as first recorded); an annotated TSV saves
  and reloads with `keys`/`[]` intact.

Corrections applied to the docs as a result: the `:pki` load-driver
paragraph in `doc/developer/PersistenceEngines.md` and the close
paragraphs in both pages were rewritten to match the observed behavior
above; the plain-`Hash` block-return error is now named explicitly.

## Test-suite evidence (2026-09-09, HEAD 8a3a514)

`test/scout/persist/**` run as a single aggregate process
(`ruby -Ilib -Itest -e 'Dir["test/scout/persist/**/test_*.rb"].sort.each{|f| require f}'`):

    36 tests, 847 assertions, 0 failures, 0 errors, 0 pendings,
    0 omissions, 0 notifications — 100% passed (3.06 s)

Per-file (individually, same totals):

| file | tests | assertions |
|---|---|---|
| persist/test_tsv.rb | 5 | 36 |
| persist/tsv/test_serialize.rb | 1 | 1 |
| persist/tsv/adapter/test_base.rb | 3 | 12 |
| persist/tsv/adapter/test_fix_width_table.rb | 1 | 3 |
| persist/tsv/adapter/test_packed_index.rb | 1 | 405 |
| persist/tsv/adapter/test_sharder.rb | 7 | 37 |
| persist/tsv/adapter/test_tokyocabinet.rb | 10 | 122 |
| persist/engine/test_fix_width_table.rb | 5 | 22 |
| persist/engine/test_packed_index.rb | 1 | 202 |
| persist/engine/test_sharder.rb | 1 | 5 |
| persist/engine/test_tokyocabinet.rb | 1 | 2 |

Skipped / empty files (not counted):

- `persist/engine/test_tkrzw.rb` and
  `persist/tsv/adapter/test_serialize.rb` are **0 bytes**.
- `persist/tsv/adapter/test_tkrzw.rb` (2939 bytes) executes zero tests:
  its whole body is wrapped in `begin ... rescue Exception` around a
  `require 'scout/tsv/adapter/tkrzw'`-equivalent require of the missing
  `tkrzw` gem, so the class never loads. **tkrzw gem absent — noted as
  skipped.**

There is no `test/scout/test_persist*.rb` at HEAD; the only other
persist-named test file is `test/scout/tsv/.save/test_persist.rb` (a
stale `.save` copy, untracked, requires a `lib/scout/tsv/.save` path that
still exists but whose sibling `test/scout/tsv/.save/persist/test_adapter.rb`
fails: `"1\t2\t3" expected but was ["1","2","3"]`). The `.save/` subtree is
scratch material, not part of the suite run by the Rake task
(`test.pattern = 'test/**/test_*.rb'` does match it, so a full `rake test`
would also pick it up — flagged as an open item for the suite owner).

## Deliberately left open

- **BDB cursor/range semantics**: TokyoCabinet-native surface, documented
  upstream; no probe populated and scanned a BDB.
- **Concurrency under load**: locking was inspected structurally
  (`read_lock`/`write_lock`, `Persist.lock_dir`, `TSVAdapter.lock_dir`)
  but no probe ran concurrent processes — the sandbox forbids forks.
- **tkrzw round-trip**: gem absent and never required; recorded as an
  availability finding only.
