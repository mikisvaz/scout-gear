# Downstream usage analysis — scout-gear features exercised by representative workflows

Repo paths (verified at baseline): `~/git/workflows/{Finances,AGS,genomics,
SyntheticCancerGenome}`. AGS rev c281257; Finances rev 793fa58.
Usage = evidence of **relevance**, not semantics. Semantics verified in
scout-gear source; pointers below.

**IMPORTANT caveat (mixed stacks):** AGS and genomics are largely **rbbt-util
based** (`require 'rbbt/workflow'`), not scout-gear. Finances and
SyntheticCancerGenome (SCG) are **scout-gear based** (`require 'scout'` /
`extend Workflow` from scout-gear). Only scout-gear-confirmed usage counts
toward scout-gear docs; rbbt-only usage is ecosystem context.

## U1. Workflow module extension + task DSL  [HIGH]

- **Finances**: `workflow.rb:9 module Finances; extend Workflow` with
  `input :quote, :string, ..., required: true` (line 12), `task :bet => :float
  do ... end`; `set_info :sell_tx, ...` inside tasks; `log :order, order`.
- **SCG**: `extend Workflow`; `dep :align, sample: :tumor` /
  `dep :align, sample: :normal` then `dependencies.flatten.compact`
  (`tasks/analyze.rb:22-25`); dep-with-block naming (`dep :clone, ... do
  |jobname,options,dependencies|`); dep on other workflow
  (`dep Sequence, :reference, ...` — cross-workflow dep via workflow object);
  `Workflow.main = SyntheticCancerGenome`.
- scout-gear evidence: workflow.rb:63 (`extended`), definition.rb (`input`,
  `task`, `dep`), step/info (`set_info`, `log`).
- **Multi-workflow: YES (2 scout-gear workflows)** — core DSL (input/task/
  dep/log/set_info/produce) is the top documentation priority.

## U2. Entity modules (`extend Entity`, `property`, `setup`)  [HIGH]

- **Finances**: `lib/entity/quote.rb:9 module Quote; extend Entity`;
  `Quote.build` → `Quote.setup(...)` canonical key strings (`quote.rb:32`);
  `property :_parts do ... end`; `Security.setup` cross-entity
  (`quote.rb:58`, `security.rb`, `order.rb:11`, `transaction.rb`).
- scout-gear evidence: entity.rb:8-19 (extended sets up format module),
  entity/property.rb (`property` DSL), Annotation#setup.
- **Multi-workflow: Finances only** (SCG uses HTS/NEATGenReads deps, no local
  Entity modules) — but Entity is a public scout-gear API with a dedicated
  doc page; Finances demonstrates real usage patterns (build/setup/property).

## U3. Persist / persist DBs  [HIGH]

- **Finances**: `Persist.persist key.to_s, :json` (`lib/sources/yfinance.rb:22`),
  `Persist.persist 'US Stocks', :json` (`stocks/us.rb:136,142`) — using
  `Persist.persist(name, type)` inside a workflow's own code (not
  Workflow#persist).
- **Finances QuoteDB**: `Persist.open_database(path.find, false, :clean,
  'BDB')` (`lib/tools/quote_db/bdb.rb:41`) — **BDB engine used directly**,
  returns TokyoCabinet extended with adapter; binary blobs with `:clean`
  serializer.
- scout-gear evidence: scout-essentials persist.rb (engine open), gear
  persist/engines (HDB/BDB in tsv adapters; Persist.open_database — verify in
  scout-essentials, referenced from Finances).
- **Multi-workflow: 1 scout-gear workflow** but two distinct usages (JSON
  memoization + BDB database). Both are doc-worthy.

## U4. TSV (`tsv` dsl on paths/streams, `TSV.open`, options)  [HIGH]

- **SCG**: `dependencies.flatten.compact`; tasks produce `.tsv` results.
- **genomics (rbbt)**: heavy `TSV.open`, `:persist => true`, `step(:x).join
  .path.tsv ... :merge => true, :type => :flat`, `TSV.paste_streams` — same
  API family; rbbt context but confirms option surface
  (`:key_field, :fields, :type, :merge, :persist, :unnamed, :stream`).
- **Finances**: QuoteDB returns TSV-ish data; `Persist.save(..., :json)`.
- scout-gear evidence: lib/scout/tsv.rb + tsv/parser.rb (options
  `:key_field, :fields, :type, :merge, :cast, :select, :sep, :sep2,
  :unnamed, :namespace, :persist` etc.).
- **Multi-workflow: YES** (3 of 4 use TSV-family APIs; 2 scout-gear).

## U5. KnowledgeBase  [MEDIUM]

- **Finances**: `require 'scout/knowledge_base'`;
  `self.knowledge_base = KnowledgeBase.new Scout.var.Finance.kb`
  (`workflow.rb:2,11`) — per-workflow KB instance bound to
  `Scout.var.Finance.kb` path.
- scout-gear evidence: knowledge_base.rb:16 (`initialize(dir, namespace)`).
- **Multi-workflow: 1** — but KB has its own doc page(s); Finances shows the
  canonical attach pattern (`self.knowledge_base =` on the workflow).

## U6. HPC / scheduler deployment  [MEDIUM — config evidence]

- Deployment rules live in `~/.scout/etc/batch` (see baseline for file
  list: `can_build`, `clean`, `containers`, `exclusive`, `lymphocyte.yaml`,
  `max_jobs.yaml`, `skipped`, `used_containers.yaml`).
- `scout workflow task --deploy SLURM` etc. (scout_commands/workflow/task);
  `Workflow.produce` → orchestrator rules → SLURM/LSF/PBS (T8 inventory).
- No downstream workflow repo ships scout-gear batch configs directly; the
  user-level `~/.scout/etc/batch` files are the real-world evidence of
  rule keys (e.g. `defaults`, per-workflow rules, `config_keys`, `cpus`,
  `time`, `containers`, `exclusive`, `skipped`).
- **Action**: document rules from source + these config files; treat file
  *names* as evidence that rule keys like `containers`, `exclusive`,
  `skip` are used in practice.

## U7. Stream/concurrency primitives  [LOW in these repos]

- No direct WorkQueue/Semaphore usage found in the 4 workflows (they get
  parallelism via `dep`/`--deploy` and `compute` options instead).
- rbbt genomics uses `TSV.paste_streams` (streaming concat).
- Conclusion: WorkQueue/Semaphore are framework-internal for these users —
  document as advanced/internal, not headline.

## U8. CLI surface used downstream  [MEDIUM]

- `scout workflow task <wf> <task> --deploy ...` (finances/bin, SCG docs?),
  `scout workflow prov`, `scout batch list/tail/clean`,
  `scout workflow install` (see `~/.scout/etc` installs).
- Verify concrete invocations in `*/bin` scripts during Phase 2 (grep
  `scout workflow` in the four repos' bin/ and README).

## Priority ranking for documentation

1. U1 workflow DSL (input/task/dep/log/set_info/produce, job naming) —
   universal.
2. U4 TSV usage patterns (options, persist, stream).
3. U2 Entity (setup/property) + U5 KB attach.
4. U3 Persist (persist + open_database/BDB).
5. U6/U8 deployment rules + CLI (`--deploy`, batch configs).
6. U7 concurrency internals — advanced section only.
### Downstream KB/Traverse usage note (post-doc-check)
- AGS (`~/git/workflows/AGS/lib/knowledge_base/AGS.rb`) uses the LEGACY
  rbbt API: `require 'rbbt/knowledge_base'`, `KnowledgeBase.new`,
  `KB.register` with `:source => 'field (Format)'` syntax — NOT the
  scout-gear `=~` syntax documented in scout-gear docs. It also uses
  `KB.format = {...}` (unverified in scout-gear source).
- No downstream workflow uses `kb.traverse` / `kb.subset` /
  `kb.neighbours` at all (grep across Finances/AGS/genomics/SCG).
  Traverse-rule docs (wildcards ?, lists :) remain source-only evidence.
- `TSV.traverse` IS used downstream (AGS NTNU.rb:39).
