# Validation Report

## Date
Generated during the scout-gear documentation reorganization.

## Methodology

The validation pass performed five checks across the entire documentation
set:

1. **Internal link integrity** — Every relative markdown link was resolved
   against the filesystem to detect broken cross-references.
2. **User doc purity** — User-facing documents were scanned for
   implementation-internal terms (class names like `Dumper`, `Transformer`,
   `TSVAdapter`, `FixWidthTable`, `TokyoCabinet`, etc.).
3. **Subsystem coverage** — All 8 major subsystems (Workflow, TSV, Entity,
   Association, KnowledgeBase, Persist, WorkQueue, Semaphore) were
   verified to appear in both user and developer documentation.
4. **Research disclaimers** — All research artifacts were checked for a
   non-normative disclaimer.
5. **File counts** — Verified the expected number of files in each layer
   and confirmed removal of all old flat documentation.

## Results

### 1. Internal link integrity: PASS
- **108 internal links checked**
- **0 broken links**
- All cross-references between user docs, developer docs, and research
  artifacts resolve correctly.
- External links to scout-essentials documentation use GitHub URLs.

### 2. User doc purity: PASS
- **0 implementation-internal terms found** in any user document.
- Terms scanned for: `Dumper`, `Transformer`, `TSVAdapter`,
  `FixWidthTable`, `PackedIndex`, `Sharder`, `TokyoCabinet`, `Tkrzw`,
  `annotate_next_task`.
- Note: The `CachingData.md` user doc does mention engine codes (`:HDB`,
  `:BDB`, etc.) because these are part of the public API that users must
  specify. The table presents them as options without naming the
  underlying implementation classes.

### 3. Subsystem coverage: PASS

| Subsystem | User doc | Developer doc |
|-----------|----------|---------------|
| Workflow | ✓ | ✓ |
| TSV | ✓ | ✓ |
| Entity | ✓ | ✓ |
| Association | ✓ | ✓ |
| KnowledgeBase | ✓ | ✓ |
| Persist | ✓ | ✓ |
| WorkQueue | ✓ | ✓ |
| Semaphore | ✓ | ✓ |

### 4. Research disclaimers: PASS
- **7 research artifacts**, all with non-normative disclaimers.

### 5. File counts: PASS

| Layer | Count |
|-------|-------|
| User docs (`doc/user/`) | 7 |
| Developer docs (`doc/developer/`) | 7 |
| Research artifacts (`research/`) | 7 |
| Old flat docs removed | 8 (all removed) |

## Issues found and fixed during validation

1. **Broken internal link** in `BuildingWorkflows.md`: Link to
   `developer/WorkflowEngine.md` was missing the `../` prefix. Fixed by
   correcting to `../developer/WorkflowEngine.md`.

2. **External URL typos**: Several links to scout-essentials documentation
   contained typos (`scoot-essentials`, `scout-truncate-essentials`,
   `dead-link`, `job.mikisvaz`). All corrected to
   `https://github.com/mikisvaz/scout-essentials/...`.

3. **Implementation internals in user docs**: The `CachingData.md` user
   doc mentioned engine implementation names (`TokyoCabinet Hash Database`,
   `TokyoCabinet B-Tree Database`, `FixWidthTable`, `PackedIndex`,
   `Sharder`, `Tkrzw`). Fixed by:
   - Simplifying the engine table to show only the engine codes (`:HDB`,
     `:BDB`, etc.) without the implementation class names.
   - Replacing `Workflow::Scheduler.produce(...)` with prose description
     in `BuildingWorkflows.md` and `Cookbook.md`.

## Final file inventory

```
doc/
    StartHere.md
    Improvements.md
    user/
        BuildingWorkflows.md
        ProcessingTabularData.md
        WorkingWithEntities.md
        ManagingRelationships
        RunningParallelWork.md
        CachingData.md
        Cookbook.md
    developer/
        Architecture.md
        DesignPrinciples.md
        WorkflowEngine.md
        TSVInternals.md
        EntitySystem.md
        PersistenceEngines.md
        ConcurrencyModel.md

research/
    00_scope_and_themes.md
    workflow-engine-analysis.md
    tsv-internals-analysis.md
    entity-association-kb-analysis.md
    persistence-concurrency-analysis.md
    design-philosophy-analysis.md
    synthesis-report.md
    validation-report.md      ← this file
```

## Conclusion

The scout-gear documentation reorganization is complete and validated.
All acceptance criteria are met:

- ✓ `doc/StartHere.md` exists and routes to all layers
- ✓ `doc/user/` contains 7 concept-oriented guides
- ✓ `doc/developer/` contains 7 architectural documents
- ✓ `research/` contains 8 investigation artifacts (including this report)
- ✓ `doc/Improvements.md` exists with 20 actionable recommendations
- ✓ All 8 old flat documentation files removed
- ✓ Zero broken internal cross-references
- ✓ No implementation internals leaked into user docs
- ✓ All 8 subsystems covered in both user and developer documentation
- ✓ Cross-references to scout-essentials use GitHub URLs
