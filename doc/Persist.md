# Persist

Persist provides a unified, engine-agnostic persistence layer for serializing, saving and loading Ruby objects and TSVs to/from files, with:

- Typed serialization for common types and TSV shapes.
- High-level caching with locking and atomic writes (Persist.persist).
- TSV-aware persistence (Persist.tsv / Persist.persist_tsv) with pluggable storage engines.
- Storage engines:
  - TokyoCabinet HDB/BDB (key-value stores) with TSVAdapter.
  - Tkrzw (HashDBM) via ScoutTKRZW.
  - FixWidthTable (position/range index with fixed-size records).
  - PackedIndex (binary-packed fixed-size rows).
  - Sharder (key-space sharding over sub-databases).
- Concurrency-safe read/write locks and metadata persistence.

Sections:
- Core API (serialize, save/load, persist)
- TSV persistence helpers
- Storage engines
  - TokyoCabinet (HDB/BDB)
  - Tkrzw (HashDBM)
  - FixWidthTable (FWT) — point/range indices
  - PackedIndex (PKI) — fixed-layout random access
  - Sharder — key-based horizontal sharding
- TSVAdapter (persistence adapters and serializers)
- Examples

---

## Core API

Serialization helpers
- Persist.serialize(content, type) / Persist.deserialize(serialized, type)
  - Types include string/text/file/path/binary, integer/float/boolean, array, json/yaml/marshal, and “_array” variants.
  - IO/StringIO are read into strings when needed; :binary writes in 'wb'.

Save/load
- Persist.save(content, file, type = :serializer)
  - Uses registered save_drivers (see below); otherwise serializes and writes atomically (Open.sensible_write).
  - Supports special type :memory (in-RAM).
- Persist.load(file, type = :serializer)
  - Uses registered load_drivers; returns typed Ruby object (or persistence-backed TSV for TSV types).

High-level caching
- Persist.persist(name, type = :serializer, options = {}) { |maybe_file| value }
  - Computes and stores a value if missing/outdated, then returns it.
  - Locks the cache file while writing to avoid races.
  - If the block yields an IO stream, Persist tees it so one copy is written to disk while the other is returned (and lock is held during streaming).
  - Common options: :dir/:path, :no_load, :update, :lockfile, :tee_copies, :prefix, :canfail.

Memory helper
- Persist.memory(name, options={}, &block) — in-process cache (type :memory).

Registered drivers (excerpt)
- Persist.save_drivers[:tsv], [:HDB], [:BDB], [:tkh], [:fwt], [:pki]
- Persist.load_drivers for the same types.

---

## TSV persistence helpers

Make working with persisted TSVs straightforward.

Persist.tsv(id, options = {}, engine: nil, persist_options: {}) { |data| ... } → TSV
- Creates/opens a persistence-backed TSV under a stable persistence path for id.
- engine (or persist_options[:engine]) chooses the backend:
  - 'HDB' (default), 'BDB', 'tkh' (Tkrzw HashDBM), 'fwt' (FixWidthTable), 'pki' (PackedIndex).
- The block is called with a “data” object (backend) to populate using TSV.open(..., data: data), or to write directly to the backend.
- Persists TSV metadata (key_field, fields, type, serializer) and returns a TSV-like object extended with TSVAdapter.

Persist.persist_tsv(file, filename=nil, options={}, persist_options={}, &block) → TSV
- Thin wrapper around Persist.tsv that extracts persist_* options from options for convenience.

Open a persistence database directly
- Persist.open_database(path, write, serializer=nil, type="HDB", options={}) → backend
  - For 'fwt': options include :value_size, :range, :update, :in_memory, :pos_function.
  - For 'pki': options include :pattern (PackedIndex mask), :pos_function.
  - For 'HDB'/'BDB'/'tkh': opens a key-value store backend.

---

## Storage engines

### TokyoCabinet (HDB/BDB)

- ScoutCabinet.open(path, write=true, 'HDB'|'BDB')
  - Returns a TokyoCabinet database extended with ScoutCabinet helpers (read/write switching, import TSV, prefix/range when BDB).
  - Used by Persist.open_tokyocabinet and the TSV adapters.

- Persist.open_tokyocabinet(path, write, serializer=nil, tokyocabinet_class='HDB') → cabinet extended with TKAdapter (inherits TSVAdapter).

- Import TSV directly (fast path):
  - ScoutCabinet.importtsv(db, stream)
  - Or db.load_stream(stream) via adapter wrapper.
  - Expects a full TSV stream (preamble + header).

Notes:
- BDB supports range/prefix queries; HDB is unordered but supports basic CRUD.
- Annotation metadata (key_field/fields/type/etc.) is persisted as a special record and re-loaded on open.

### Tkrzw (HashDBM)

- ScoutTKRZW.open(path, write=true, persistence_class='tkh', options={}) → Tkrzw::DBM extended with ScoutTKRZW
  - options include truncate, num_buckets, sync_hard, encoding, etc.
  - Works similarly to ScoutCabinet and integrates with TSVAdapter via Persist.save_drivers[:tkh]/load_drivers[:tkh].

### FixWidthTable (FWT)

A compact file format for large position/range indices with constant record size:

- FixWidthTable.new(path, value_size, range=false, update=false, in_memory=true)
  - value_size: bytes reserved per value.
  - range: true to store (start,end) with overlap counters (for range indices), false for single positions.
  - update: create/truncate when true (or when file missing).
  - in_memory: load file into memory (StringIO) for faster reads.

- Adding data:
  - add_point([value, pos]) or f.add_point(tsv) — expects TSV keyed by pos or with a field.
  - add_range(value_table) — expects TSV with Start and End fields; internally calls add_range_point for each record.

- Query:
  - f[pos] — returns values overlapping pos (Integer or Range). With range==false, point lookups; with range==true, range overlaps.
  - f.overlaps(pos, value=false) — returns overlapping record positions (or “start:end(:value)” strings when value=true).
  - f.values_at(*positions), f.chunked_values_at(keys, max=5000).

- Adapter:
  - Persist.open_fwt(path, value_size, range=false, serializer=nil, update=false, in_memory=false, &pos_function) → FixWidthTable extended with FWTAdapter (TSVAdapter).
  - Save/load via Persist.save_drivers[:fwt]/load_drivers[:fwt].

Example:
```ruby
# Build a range index from a TSV of intervals [Start, End]
f = Persist.open_fwt("ranges.fwt", 100, true)
f.add_range(tsv_with_start_end)
f.read
f[3]       # => %w(a b d)
f[1..6]    # => ["b"]
f.overlaps(1, true) # => ["1:6:b"]
```

### PackedIndex (PKI)

A binary file with fixed-size rows according to a format mask:

- mask elements:
  - "i"/"I" → 32/64-bit integer (internally "l"/"q").
  - "f"/"F" → float/double ("f"/"d").
  - "23s" → fixed 23-byte string ("a23").
  - "<code>:<n>" → raw bytes specification.

- PackedIndex.new(path, write=false, pattern=nil)
  - When write=true, pattern must be provided; when reading, pattern is loaded from file header.
  - << payload — write a row (payload.pack(mask)), or write nil as a NIL sentinel.
  - [position] — read a row at position (returns nil for NIL rows).
  - values_at(*positions), size.

- Adapter:
  - Persist.open_pki(path, write, pattern, &pos_function) → PackedIndex extended with PKIAdapter (TSVAdapter).
  - PKIAdapter adds convenience: add(key,value) with Numeric key (skips with NILs), [] supporting pos_function (e.g., parse "chr:pos").

Example:
```ruby
pi = Persist.open_pki("packed.idx", true, %w(i i 23s f f))
100.times { |i| pi << [i, i+2, i.to_s * 10, rand, rand] }
pi << nil # NIL row
pi.close

pi = Persist.open_pki("packed.idx", false, %w(i i 23s f f))
pi[10] # => [10, 12, "1010101010", 0.123..., 0.456...]
```

### Sharder

Horizontally shards key-value storage across multiple underlying databases based on a shard function:

- Sharder.new(persistence_dir, write=false, db_type='HDB', persist_options={}, &shard_function)
  - shard_function (Proc) maps a key to a shard name (string/number).
  - Each shard lives under <dir>/shard-<name> as a separate backend (HDB/BDB/tkh/fwt/pki depending on db_type/options).

- Access:
  - sharder[key] / sharder[key] = value — routes to the shard’s database.
  - database(key) — returns shard backend for a key.
  - size, keys, each, include?, prefix(key) (when supported by backend, e.g. BDB range).

- Persist.open_sharder(persistence_dir, write=false, db_type=nil, persist_options={}, &shard_function) → Sharder extended with ShardAdapter (TSVAdapter).
  - ShardAdapter saves TSV metadata in <dir>/metadata, exposes TSV-like API, merges keys/size across shards.

- Combining with TSV persistence:
  - Persist.tsv(..., persist_options: { shard_function: ->(k){ ... } }) { |data| TSV.open(file, data: data, ...) }

Examples:
```ruby
# Split by last character of key
sh = Persist.open_sharder("shards", true, :HDB, shard_function: ->(k){ k[-1] })
sh["key-a"] = "a"
sh["key-b"] = "b"
sh["key-a"] # => "a"

# Shard TSV by last char of ID
sh_tsv = Persist.tsv("my-sharded-tsv", persist_options: { shard_function: ->(k){ k[-1] } }) do |data|
  TSV.open(tsv_path, data: data, type: :list)
end
sh_tsv["id1"]["ValueA"] # => "a1"
```

---

## TSVAdapter

TSVAdapter turns key-value stores and engine wrappers into TSV-like objects with:

- Annotations: key_field, fields, type, filename, namespace, identifiers, serializer, unnamed.
- Concurrency:
  - read/write/close with flags (read?, write?, closed?).
  - read_lock/write_lock, with_read/with_write for safe critical sections.
  - File-based lock in TSVAdapter.lock_dir (tmp/tsv_locks) around write transitions.

- Serialization:
  - Per-TSV serializer for values. Defaults depend on type:
    - :single → StringSerializer
    - :list/:flat → StringArraySerializer
    - :double → StringDoubleArraySerializer
    - :integer/_array, :float/_array, :marshal, :json, :binary, :tsv, etc.
  - Accessors wrap/unpack values transparently:
    - tsv["key"] returns decoded (and NamedArray-wrapped) values.
    - tsv.orig_get("key") returns encoded raw storage.

- Metadata persistence:
  - Cabinet/PKI/FWT/Sharder adapters persist the annotation hash either in a special record (key "__annotation_hash__") or a sidecar metadata file (.metadata).
  - On open, adapters load metadata and re-annotate the backend as a TSV.

- Helpers:
  - keys, each, size filter out the special annotation record.
  - prefix(key) and range (when backend supports them; BDB provides range).
  - merge!(hash), values_at(*keys), collect/map, include?

Serializer modules (subset):
- :integer IntegerSerializer, :float FloatSerializer
- :integer_array IntegerArraySerializer (with NIL sentinel), :float_array FloatArraySerializer
- :strict_integer_array/:strict_float_array (pack/unpack only)
- :string StringSerializer, :binary BinarySerializer
- :marshal Marshal, :json JSON
- :tsv TSVSerializer (dump TSV.to_s; load TSV.open)
- :marshal_tsv TSVMarshalSerializer (Marshal.dump/load TSV)

Example:
```ruby
tsv = Persist.open_tokyocabinet("db.hdb", true)
TSV.setup(tsv, key_field: "Key", fields: %w(One Two), type: :list)
tsv.extend TSVAdapter
tsv.serializer = :marshal
tsv["a"] = [1, 2]
tsv["a"] # => [1, 2]
Marshal.load(tsv.orig_get("a")) # => [1, 2]
```

---

## Examples

Basic persist and reload:

```ruby
# Cache a TSV under a logical id
content = <<~EOF
#: :sep=/\\s+/#:type=:double#:merge=:concat
#Id ValueA ValueB OtherID
row1 a|aa|aaa b Id1|Id2
row2 A B Id3
row2 a a id3
EOF

tsv = Persist.persist("TEST Persist TSV", :tsv) do
  TmpFile.with_file(content) { |file| TSV.open(file) }
end

# Subsequent calls load cached TSV even if block raises
tsv2 = Persist.persist("TEST Persist TSV", :tsv) { raise "won't run" }
```

Persist.tsv (populate into a specific backend):

```ruby
tsv = Persist.tsv("Some TSV") do |data|
  TSV.open("input.tsv", persist_data: data)  # data is the persistence backend
end
tsv["row1"]["ValueB"] # => ["b"]
```

Open cabinets and import TSV quickly:

```ruby
parser = TSV::Parser.new("big.tsv", type: :double)
db = ScoutCabinet.open("big.hdb", true, :HDB)
parser.with_stream { |stream| ScoutCabinet.importtsv(db, stream) }
db.write_and_read do
  TSV.setup(db, **parser.options)
  db.extend TSVAdapter
end
db["row2"]["ValueA"] # => ["A","AA"]
```

FixWidthTable for ranges:

```ruby
f = Persist.open_fwt("ranges.fwt", 100, true)
f.add_range(range_tsv)  # TSV with Start/End
f.read
f[3]           # => keys overlapping position 3
f[3..4]        # => keys overlapping range 3..4
f.overlaps(1)  # => ["1:6"]
```

PackedIndex:

```ruby
pi = Persist.open_pki("packed.idx", true, %w(i i 23s f f))
100.times { |i| pi << [i, i+2, i.to_s*10, rand, rand] }
pi << nil  # sparse rows
pi.close

pi = Persist.open_pki("packed.idx", false, %w(i i 23s f f))
pi[10] # => [10, 12, "1010101010", 0.x, 0.y]
```

Sharded TSV (HDB):

```ruby
sh = Persist.tsv("sharded", persist_options: { shard_function: ->(k){ k[-1] } }) do |data|
  TSV.open("table.tsv", data: data, type: :list)
end
sh["id1"]["ValueA"]     # => "a1"
sh.prefix("id1")        # requires BDB engine to support range/prefix
```

Tkrzw:

```ruby
db = ScoutTKRZW.open("tk.tkh", true)
1000.times { |i| db["foo#{i}"] = "bar#{i}" }
db.close
db2 = ScoutTKRZW.open("tk.tkh", false)
db2.keys.length # => 1000
```

Float arrays with typed serializer:

```ruby
tsv = TSV.open("values.tsv", persist: true, type: :list, cast: :to_f, persist_update: true)
tsv.serializer # => TSVAdapter::FloatArraySerializer
tsv["row1"]    # => [0.2, 0.3, 0.0]
```

---

Persist centers the framework’s caching and storage patterns: a single entry point to save/load arbitrary objects, plus first-class TSV persistence on top of multiple storage engines, with safe locking and atomicity. Use Persist.persist for general caches; use Persist.tsv or Persist.persist_tsv when dealing with TSV-shaped data and pick the engine that best matches your workload (HDB/BDB/tkh for generic KV stores, FWT for range/position indices, PKI for compact fixed-layout records, Sharder to scale by shards).