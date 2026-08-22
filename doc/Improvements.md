Truncated (9624): # Improvements

Actionable recommendations for code improvements, bug fixes, and
architectural refinements discovered during the documentation audit.

These are based on research artifacts in `research/`. They are
prioritized by impact and effort. Each item cites its source evidence.

## Summary

| Priority | Category | Count |
|----------|----------|-------|
| High | Bugs / Correctness | 5 |
| High | Architecture | 4 |
| Medium | Missing Features / Docs | 5 |
| Low | Code Quality | 6 |
| | **Total** | **20** |

---

## High priority — Bugs / Correctness

### H1. Dead code: `cleaned_dependencies` always returns `[]`

**Location**: `lib/scout/workflow/step/status.rb:33-39`
**Evidence**: The method body starts with `return []` (line 34); the
subsequent selection logic is unreachable.
**Issue**: Callers cannot observe cleaned dependencies; the guard may
mask dependency cleanup bugs.
**Recommendation**: Either restore the intended behavior or remove the
method and its callers.
**Effort**: Low.

### H2. `REMOVE_TASK_ALIAS` behavior is subtle and error-prone

**Location**: `lib/scout/workflow/definition.rb:151-179`
**Evidence**: `REMOVE_TASK_ALIAS` is derived from
`SCOUT_REMOVE_TASK_ALIAS` / `SCOUT_REMOVE_DEP_TASKS` /
`RBBT_REMOVE_DEP_TASKS` env tokens, and `remove_dep_tasks` config
overrides it per call site.
**Issue**: These settings gate whether `task_alias` jobs keep their
dependency sub-jobs in the final tree (`task_alias` runs the last
dependency and may drop the alias job itself); the effects depend on
env/config in ways that are easy to get wrong (the flag names talk about
"removing" tasks but they actually control forgetting/alias-collapsing).
**Recommendation**: Document the gating explicitly in
WorkflowEngine.md or replace with an explicit task option.
**Effort**: Medium.

### H3. Missing `inline` gem makes `Semaphore` methods undefined

**Location**: `lib/scout/semaphore.rb:1-10`
**Evidence**: P032. When the `inline` gem cannot be used, the module logs
"semaphore synchronization will not work" and is not defined, so any
later `Semaphore.*` call raises `NoMethodError` — it fails loudly, not
silently, and there is no no-op fallback.
**Issue**: The failure point is far from the missing gem (any first
semaphore use), and the error is a bare `NoMethodError` on
`Semaphore`.
**Recommendation**: Fail at load time (or wrap semaphore entry points
with a descriptive error naming the missing `inline` dependency); a
`flock`-based fallback would also remove the hard dependency.
**Effort**: Low.

### H4. WorkQueue non-serializable blocks fail late

**Location**: `lib/scout/work_queue.rb` (worker fork + Marshal)
**Issue**: Blocks or captured variables that are not
Marshal-serializable raise inside the forked worker, which surfaces as a
confusing worker-side error rather than a clear pre-flight failure.
**Recommendation**: Pre-flight Marshal check with a descriptive error.
**Effort**: Medium.

### H5. Info serializer change may break old info files

**Location**: `lib/scout/workflow/step/info.rb:6`
**Evidence**: `SERIALIZER` is read from scout config
(`:serializer`/`:step_info`/`:info`/`:step`, env `SCOUT_SERIALIZER`)
with default `:json`; values are dumped per-key with the selected
serializer.
**Issue**: Reading info written by an older default with a different
serializer setting may fail or produce opaque values.
**Recommendation**: Detect the per-file format before parsing and warn
on legacy formats.
**Effort**: Medium.

## High priority — Architecture

### A1. TSV `attach` match-key auto-detection can surprise

**Location**: `lib/scout/tsv/attach.rb`
**Issue**: When the match key is not explicit, `attach` infers it from
shared field names; multiple candidates resolve by convention rather
than by error.
**Recommendation**: Warn (or require explicit `match_key`) when more
than one candidate exists.
**Effort**: Medium.

### A2. Step path derivation is complex

**Location**: `lib/scout/workflow/step.rb` (path/digest computation)
**Issue**: The job path derives from a digest of inputs,
non-default inputs and dependencies, with configuration-dependent
branches; the result is hard to predict.
**Recommendation**: Document the derivation in WorkflowEngine.md and
consider extracting it into a testable unit.
**Effort**: Medium.

### A3. Property dispatch types have many edge cases

**Location**: `lib/scout/entity/property.rb:42-97`
**Issue**: Dispatch types (`:single`, `:array`, `:multiple`, `:both`,
plus `MultipleEntityProperty`) interact non-obviously, particularly for
array receivers.
**Recommendation**: Keep the dispatch table in EntitySystem.md current;
consider deprecating `:both`.
**Effort**: Medium.

### A4. Namespace handling is inconsistent

**Location**: `lib/scout/tsv.rb`, `lib/scout/entity/*`,
`lib/scout/knowledge_base.rb`
**Issue**: Namespaces appear as String module names, Symbols, or path
fragments depending on context, complicating identifier-file resolution.
**Recommendation**: Standardize on String module names and validate on
`setup`.
**Effort**: Low.

## Medium priority — Missing features / Documentation

### M1. `unnamed` parameter is under-documented

**Location**: `lib/scout/tsv.rb` (parser options)
**Issue**: `unnamed: true` (fields accessible by position, not name) is
a common performance option but is only documented in passing.
**Recommendation**: Document in ProcessingTabularData.md and
TSVInternals.md.
**Effort**: Low.

### M2. Scheduler rules format is only in one page

**Location**: `lib/scout/workflow/deployment/orchestrator/rules.rb`
**Issue**: The rules hash (defaults/skip/chains and per-job batch
options) is documented in HPCBatchExecution.md but not referenced from
Configuration documentation.
**Recommendation**: Cross-link from configuration docs.
**Effort**: Low.

### M3. Identifier translation semantics need a dedicated section

**Location**: `lib/scout/tsv/change_id/translate.rb`
**Issue**: Identifier files are ordinary TSVs whose header field names are
the identifier formats (no per-pair file naming). The translate/index
chain mechanics (`translation_path`, `translation_index`, parenthesized
header rewriting) were only partly covered and were previously described
with a nonexistent `<source>%to<target>` file-naming convention.
**Recommendation**: The mechanism is now documented in
ProcessingTabularData.md and WorkingWithEntities.md; keep those two
descriptions consistent.
**Effort**: Low.

### M4. Entity `:both` dispatch type is non-intuitive

**Location**: `lib/scout/entity/property.rb`
**Issue**: `:both` makes one property serve String and Array receivers
with different block arities; easy to misuse.
**Recommendation**: Include worked examples (EntitySystem.md already
carries a dispatch table).
**Effort**: Low.

### M5. KnowledgeBase traverse rules syntax is barely documented

**Location**: `lib/scout/knowledge_base/traverse.rb`
**Issue**: The rules DSL (association names with directions and
conditions) is documented only briefly.
**Recommendation**: Expand ManagingRelationships.md with real rule
examples from the test-suite.
**Effort**: Low.

## Low priority — Code quality

### L1. `TSV::Parser` duplicates per-type parsing logic

**Location**: `lib/scout/tsv/parser.rb`
**Issue**: Value-type parsing (`:single`, `:list`, `:flat`, `:double`)
shares structure but is duplicated.
**Recommendation**: Factor common logic.
**Effort**: Medium.

### L2. Info file writes are not atomic

**Location**: `lib/scout/workflow/step/info.rb`
**Issue**: Concurrent readers can observe partially-written info files.
**Recommendation**: Write-then-rename.
**Effort**: Low.

### L3. ConcurrentStream cleanup belongs upstream

**Location**: scout-essentials (`ConcurrentStream`)
**Issue**: Abnormal exits may leave zombie processes or pipes.
**Recommendation**: Fix upstream; scout-gear only consumes
ConcurrentStream.
**Effort**: Medium (upstream).

### L4. Persist path resolution has many edge cases

**Location**: scout-essentials (`lib/scout/persist.rb`) plus scout-gear
engine wrappers
**Issue**: Identifier → persistence-path conversion special-cases
strings, files and TSV objects.
**Recommendation**: Extract and test as a unit.
**Effort**: Medium.

### L5. Scheduler job state tracking can be fragile

**Location**: `lib/scout/workflow/deployment/scheduler/`
**Issue**: Corrupted or manually edited batch directories produce
confusing states.
**Recommendation**: Validate batch directories; add a repair option.
**Effort**: Medium.

### L6. RubyInline build cache is not self-cleaning

**Location**: `lib/scout/semaphore.rb`
**Issue**: Compiled semaphore extensions accumulate under the user temp
directory.
**Recommendation**: Version-stamp and prune stale builds.
**Effort**: Low.

---

## How to use this document

1. Review high-priority items first (H1–H5, A1–A4): they represent
   correctness and architectural concerns that can cause silent
   failures.
2. Consult `research/` artifacts for the underlying evidence; each item
   cites its source location.
3. Track resolution status per item (resolved / partial / won't-fix).
