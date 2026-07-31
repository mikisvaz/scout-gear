# Improvements

This document lists actionable recommendations for code improvements, bug
fixes, and architectural refinements discovered during the documentation
effort.

These are based on the research artifacts in `research/`. They are
prioritized by impact and effort.

## Summary

| Priority | Category | Count |
|----------|----------|-------|
| High | Bugs / Correctness | 5 |
| High | Architecture | 4 |
| Medium | Missing Features / Docs | 5 |
| Low | Code Quality | 6 |
| | **Total** | **20** |

---

## High priority

### H1. Dead code: `cleaned_dependencies` always returns `[]`

**Location**: `lib/scout/workflow/step.rb`
**Issue**: The `cleaned_dependencies` method always returns an empty
array, which may mask dependency cleanup bugs.
**Recommendation**: Either implement the intended behavior (detecting
dependencies that have been cleaned) or remove the method and its callers.
**Effort**: Low.

### H2. `REMOVE_TASK_ALIAS` behavior is subtle and error-prone

**Location**: `lib/scout/workflow.rb`, task alias resolution
**Issue**: The `REMOVE_TASK_ALIAS` environment variable alters task name
resolution in ways that are not intuitive. Task names may silently differ
from their declared names.
**Recommendation**: Document the behavior clearly or replace with an
explicit API (e.g., `task :name, alias: false`).
**Effort**: Medium.

### H3. Semaphore no-op fallback can cause silent race conditions

**Location**: `lib/scout/semaphore.rb`
**Issue**: When the C compiler is unavailable, Semaphore operations become
no-ops. Code that depends on locking will silently fail to synchronize,
leading to race conditions.
**Recommendation**: Raise an error (or log a warning) when Semaphore is
used but C extensions are not available. Consider providing a pure-Ruby
fallback using `flock`.
**Effort**: Low.

### H4. WorkQueue non-serializable blocks fail silently in some cases

**Location**: `lib/scout/work_queue.rb`
**Issue**: If the worker block or captured variables are not
Marshal-serializable, the error may not surface immediately, leading to
confusing debugging.
**Recommendation**: Add a pre-flight check that attempts to Marshal the
block and inputs before forking workers. Raise a descriptive error if it
fails.
**Effort**: Medium.

### H5. Info file serialization format change breaks backward compatibility

**Location**: `lib/scout/workflow/step.rb` (info file read/write)
**Issue**: The info file serialization changed from Marshal to JSON. Old
info files may not be readable by newer versions.
**Recommendation**: Add a format detection step that reads the first few
bytes to determine whether the info file is JSON or Marshal, and parse
accordingly. Log a warning when encountering an old format.
**Effort**: Medium.

## High priority — Architecture

### A1. TSV `attach` auto-detection of match keys is unreliable

**Location**: `lib/scout/tsv/attach.rb`
**Issue**: When `match_key` is not explicitly specified, `attach`
auto-detects the matching key by looking for common field names. This can
produce surprising results when multiple fields could match.
**Recommendation**: When multiple candidates exist, warn the user and
require explicit `match_key:`. Consider making auto-detection opt-in.
**Effort**: Medium.

### A2. Workflow Step path derivation is complex

**Location**: `lib/scout/workflow/step.rb`
**Issue**: The path derivation logic (computing the digest from inputs and
dependencies) has many special cases and configuration-dependent branches.
This makes it hard to predict the resulting path.
**Recommendation**: Document the path derivation algorithm explicitly in
the developer docs. Consider extracting it into a separate, testable
class.
**Effort**: Medium.

### A3. Property dispatch types are complex

**Location**: `lib/scout/entity.rb`
**Issue**: The five property dispatch types (`:single`, `:array`,
`:multiple`, `:both`) have many edge cases and interact in non-obvious
ways, especially for collections.
**Recommendation**: Document each type with examples. Consider deprecating
`:both` in favor of explicit dispatch.
**Effort**: Medium.

### A4. Namespace annotation is used inconsistently

**Location**: `lib/scout/tsv.rb`, `lib/scout/entity.rb`,
`lib/scout/knowledge_base.rb`
**Issue**: The `namespace` annotation is sometimes a String (module name),
sometimes a Symbol, and sometimes a path. This causes ambiguity in
identifier file resolution.
**Recommendation**: Standardize namespace as a String (module name) across
the codebase. Validate on `setup`.
**Effort**: Low.

## Medium priority — Missing features / Documentation

### M1. No explicit documentation for TSV `unnamed` parameter

**Location**: `lib/scout/tsv.rb`
**Issue**: The `unnamed` parameter (when true, fields are accessible by
position but not by name) is not documented anywhere.
**Recommendation**: Document `unnamed` in the user docs (Processing
Tabular Data) and in the TSVInternals developer doc.
**Effort**: Low.

### M2. Scheduler rules format is not documented

**Location**: `lib/scout/workflow/deployment/scheduler/`
**Issue**: The scheduler rules hash format is not documented anywhere.
Users must read the source to understand it.
**Recommendation**: Document the rules format, including all supported
keys (cpus, time, mem, queue, container) with examples.
**Effort**: Low.

### M3. Identifier file convention is not documented

**Location**: Convention: `var/<namespace>/identifiers/<source>%to<target>`
**Issue**: The identifier file naming convention is critical for entity
identifier translation but is not documented in user-facing docs.
**Recommendation**: Add a section to WorkingWithEntities user doc
explaining the convention and how to create identifier files.
**Effort**: Low.

### M4. Entity `:both` dispatch type behavior is non-intuitive

**Location**: `lib/scout/entity.rb`
**Issue**: The `:both` dispatch type is difficult to understand and may
not behave as expected for collections.
**Recommendation**: Add examples to the developer docs showing when to use
each dispatch type.
**Effort**: Low.

### M5. Association/KnowledgeBase traversal path syntax is not documented

**Location**: `lib/scout/knowledge_base.rb`
**Issue**: The traversal path syntax (e.g., `"pathway;geneprotein"`) is
not documented in user-facing docs.
**Recommendation**: Document the path syntax in the ManagingRelationships
user doc with examples.
**Effort**: Low.

## Low priority — Code quality

### L1. `TSV::Parser` has duplicated parsing logic

**Location**: `lib/scout/tsv/parser.rb`
**Issue**: The parsing logic for different value types (`:single`,
`:list`, `:flat`, `:double`) has significant duplication.
**Recommendation**: Refactor to extract common patterns into a shared
method.
**Effort**: Medium.

### L2. Info file writes are not atomic

**Location**: `lib/scout/workflow/step.rb`
**Issue**: Reading the info file may see a partially-written file if it's
being updated concurrently.
**Recommendation**: Write to a temporary file and rename atomically.
**Effort**: Low.

### L3. ConcurrentStream close semantics are fragile

**Location**: scout-essentials (ConcurrentStream)
**Issue**: If a process exits abnormally, stream cleanup may not happen,
leaving zombie processes or pipes.
**Recommendation**: Ensure `at_exit` hooks clean up streams. Consider a
heartbeat mechanism for long-running streams.
**Effort**: Medium.

### L4. Persist path resolution has many edge cases

**Location**: `lib/scout/persist.rb`
**Issue**: Path resolution has many special cases for different identifier
types (strings, files, TSV objects).
**Recommendation**: Extract path resolution into a separate class for
testability and documentation.
**Effort**: Medium.

### L5. Scheduler job state tracking can be fragile

**Location**: `lib/scout/workflow/deployment/scheduler/`
**Issue**: Scheduler job state tracking can be fragile if the batch
directory is corrupted or modified manually.
**Recommendation**: Add validation for batch directory state. Provide a
`--repair` CLI option.
**Effort**: Medium.

### L6. RubyInline C compilation cache is not self-cleaning

**Location**: `lib/scout/semaphore.rb` (RubyInline compilation)
**Issue**: The C extension cache in `~/.scout/tmp` is never cleaned up and
can accumulate stale builds.
**Recommendation**: Add a cache cleanup mechanism (e.g., version-based
invalidation).
**Effort**: Low.

---

## How to use this document

1. **Review the high-priority items first** (H1–H5, A1–A4). These represent
   correctness issues and architectural concerns that may cause silent
   failures or confusion.
2. **Use the research artifacts** for deeper understanding of any issue.
   Each item references the relevant source files.
3. **Track resolution status** by marking items as resolved, partially
   resolved, or won't-fix.
