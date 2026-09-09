Truncated (9624): # Improvements

Actionable recommendations for code improvements, bug fixes, and
architectural refinements discovered during the documentation audit.

These are based on research artifacts in `research/`. They are
prioritized by impact and effort. Each item cites its source evidence.

## Summary

| Priority | Category | Count |
|----------|----------|-------|
| High | Bugs / Correctness | 8 |
| High | Architecture | 19 |
| Medium | Missing Features / Docs | 28 |
| Low | Code Quality | 13 |
| | **Total** | **68** |

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

### H6. `WorkQueue#abort` leaves `join` permanently blocked

**Location**: `lib/scout/workflow/work_queue.rb:154`
**Issue**: `abort` kills the workers and posts the peer semaphores but never
closes the parent's output write-end, so the reader thread blocks in
`Socket#load` forever; a bare `wq.join` after `wq.abort` hangs.
Only `clean` (as `TSV.traverse(cpus:)` pairs it) unblocks the caller.
**Evidence**: `Observation/probe/wq_fork_run_da96535a53997a47f526b18869bb0c2a.json`
**Recommendation**: Close `@output.swrite` in `abort`, or make `join` not
wait on a reader that can never be satisfied.
**Effort**: Medium.

### H7. `scout workflow process` cannot load (dead documented entry point)

**Location**: `scout_commands/workflow/process`, `lib/scout/workflow/deployment/orchestrator/`
**Issue**: The command requires `scout/workflow/deployment/orchestrator`, but
the repo ships `orchestrator/` as a directory (batches/chains/rules/workload)
with no `orchestrator.rb`, so the require fails before any option block runs.
`doc/user/HPCBatchExecution.md`'s documented entry point is dead.
**Evidence**: `Observation/probe/cli_process_trace_broken_commands_85ed34c1130d05f565a61fdc3f3170ed.json`
**Recommendation**: Add `orchestrator.rb` requiring the directory's parts.
**Effort**: Low.

### H8. `scout workflow trace` cannot load

**Location**: `scout_commands/workflow/trace` (via `rbbt/workflow/util/trace`)
**Issue**: Requiring the trace utility raises
`NoMethodError: undefined method 'var' for module Rbbt` from rbbt-util's
`R/model.rb`, before the command's option block runs, so no flag works
around it.
**Evidence**: `Observation/probe/cli_process_trace_broken_commands_85ed34c1130d05f565a61fdc3f3170ed.json`
**Recommendation**: Guard or vendor the rbbt-util trace path.
**Effort**: Medium (upstream-coupled).

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

### A5. `TSV.change_key` class entry point is broken

**Location**: `lib/scout/tsv/change_id.rb:7`, `lib/scout/tsv/parser.rb:375`
**Issue**: `TSV.change_key(filename, ...)` raises
`ArgumentError: wrong number of arguments (given 2, expected 1)`: it calls
`Parser#identify_field` with `strict:`, which the parser does not accept.
The instance method `TSV#change_key` works.
**Evidence**: `Observation/probe/tsv_change_id_translate_fdafb76c464ed95d7b9db869cd94b451.json`
**Recommendation**: Accept (or drop) `strict:` in `identify_field`.
**Effort**: Low.

### A6. Streaming `attach` with a plain TSV/Hash `target:` raises a bare `TypeError`

**Location**: `lib/scout/tsv/attach.rb`
**Issue**: On the stream path only `target: :stream` is supported, but a
plain TSV/Hash target fails with
`TypeError: no implicit conversion of nil into Array` instead of a useful
message.
**Evidence**: `Observation/probe/tsv_attach_target_1a73c081a72b1d9be4dda96cd44b0c2a.json`
**Recommendation**: Detect and reject non-`:stream` targets with a
descriptive error, or materialize them.
**Effort**: Low.

### A7. `unzip` ignores the key field when resolving a field name

**Location**: `lib/scout/tsv/util.rb`
**Issue**: Resolving a field that is the (possibly composite) key raises
`TypeError`; resolution only consults `fields`, never `key_field`.
**Evidence**: `Observation/probe/tsv_util_small_tools_ff70c0c8f7aa0aa77888873737e7b9ca.json`
**Recommendation**: Include `key_field` in `identify_field`-style resolution.
**Effort**: Low.

### A8. `Sharder#write_and_read`/`write_and_close` call a method that does not exist

**Location**: `lib/scout/persist/engine/sharder.rb:129,144`
**Issue**: Both raw-engine methods call `TSV.lock_dir`, but `lock_dir` lives
on `TSVAdapter`, not `TSV`, so they raise
`NoMethodError: undefined method 'lock_dir' for module TSV`; only the
adapter-level path works.
**Evidence**: `Observation/probe/persist_adapter_matrix_531d4e97b1f8de37c0c190ddb0c0160a.json`
**Recommendation**: Route through the adapter lock helper.
**Effort**: Low.

### A9. `TSV.open(db_path, persist: true)` silently builds a fresh garbage-keyed database

**Location**: `lib/scout/tsv/open.rb`
**Issue**: Opening a database *path* with `persist: true` keys on
`TSV:<abs path>`, builds a fresh empty database and reports the annotation
blob as binary garbage keys, instead of erroring or reopening the rows.
**Evidence**: `Observation/probe/persist_tsv_open_roundtrip_4d717a6d83ac4d3a9aebab5c0c2d3299.json`
**Recommendation**: Detect a database file and reopen through `Persist.load`.
**Effort**: Medium.

### A10. No `:pki` load driver

**Location**: `lib/scout/persist/engine.rb` (`load_drivers`)
**Issue**: `Persist.load(path, :pki)` raises
`RuntimeError: Persist does not know :pki` although the index is
self-describing on disk (mask in the 8-byte header); reopening otherwise
mis-parses with `TypeError`.
**Evidence**: `Observation/probe/persist_fwt_pki_surface_7309a411094733c9eb924483055f5f81.json`
**Recommendation**: Register a `:pki` load driver that reopens from the
header (re-supplying `pos_function` when needed).
**Effort**: Medium.

### A11. `Persist::CONNECTIONS` is never invalidated by `close`

**Location**: `lib/scout/persist/engine/tokyocabinet.rb`, `lib/scout/persist.rb`
**Issue**: After `close` the object stays in `CONNECTIONS`, so a later open
of the same path hands back the closed object; writes still land but reads
are stale and `@closed`/`@writable` are not a coherent observable state.
**Evidence**: `Observation/probe/persist_engine_lifetime_a83c1d3350ce1bdbc04cc95d62ff1f70.json`
**Recommendation**: Delete the path from `CONNECTIONS` in `close`.
**Effort**: Low.

### A12. `Socket#dump` silently truncates Integer frames

**Location**: `lib/scout/workflow/socket.rb`
**Issue**: The `I` frame packs the value into the 4-byte signed size field,
so `dump(-1)` loads as `4294967295` and `dump(2**40)` as `0` — silent
corruption for any Integer outside signed 32-bit.
**Evidence**: `Observation/probe/wq_socket_framing_7be796261ae0a9e2306c89ef161b0d82.json`
**Recommendation**: Raise on out-of-range Integers or marshal them in an
`S` frame.
**Effort**: Low.

### A13. `ScoutSemaphore.fork_each_on_semaphore` is broken on entry

**Location**: `lib/scout/semaphore.rb:337`
**Issue**: It calls `Misc.fingerprint`, which does not exist (the API lives
on `Log`), so the method raises
`NoMethodError: undefined method 'fingerprint' for module Misc` before any
work runs.
**Evidence**: `Observation/probe/wq_semaphore_semantics_da869a640094600c2036d6ce2f793444.json`
**Recommendation**: One-line fix to the correct receiver.
**Effort**: Low.

### A14. `scout doc` crashes on a missing module and is empty with none

**Location**: `scout_commands/doc`
**Issue**: `scout doc <module>` crashes with
`NoMethodError: undefined method 'read' for nil` (exit 255) when the
documentation package is absent; `scout doc` with no module exits 0 with
empty output and no listing.
**Evidence**: `Observation/probe/cli_dispatch_and_surface_0d0d9c3737260738edac0c6b0087e48c.json`
**Recommendation**: Validate the doc dir and list available modules.
**Effort**: Low.

### A15. `Workflow#SOPT_str` is broken in two ways

**Location**: `lib/scout/workflow/usage.rb:103,115,315,327`
**Issue**: The module form references a local never assigned (`NameError`
on `short`) and `Workflow#get_SOPT` inherits it; the task form raises
`NoMethodError: undefined method 'recursive_inputs' for nil` for a task
absent from `self.tasks`. Latent for the shipped CLI (no in-repo caller),
live for library users.
**Evidence**: `Observation/probe/usage_sopt_str_bug_status_366e30a9aa316bf36051001677d67e03.json`
**Recommendation**: Restore the intended behavior or remove the method and
its callers.
**Effort**: Low.

### A16. `Entity.formats` collisions are silently first-write-wins

**Location**: `lib/scout/entity.rb` (`formats` registry)
**Issue**: Registration uses `||=`, so the losing module is undiscoverable
after the fact; two workflows registering the same format name silently
keep the first.
**Evidence**: `Observation/probe/entity_format_registry_a1b43a2f5f931fe0732c3f3aa79192e8.json`
**Recommendation**: Warn or raise on a conflicting re-registration.
**Effort**: Low.

### A17. `:annotation`-repo persistence crashes for array-valued properties

**Location**: `lib/scout/tsv/annotation.rb` (`load_tsv_values`/`obj_tsv_values`)
**Issue**: Persisting an array-valued property with
`annotation_repo:` raises `NoMethodError` in the top-level `Annotation`
helpers; single values round-trip.
**Evidence**: `Observation/probe/entity_persist_annotation_repo_layout_e46fc37321c4b8eaae7c328bd1ae05ef.json`
**Recommendation**: Handle array values in the annotation TSV helpers.
**Effort**: Medium.

### A18. `done_batch?` skips errored steps whose pid is the current process

**Location**: `lib/scout/workflow/deployment/scheduler/` (resume path)
**Issue**: `done_batch?` is `done? || running? || (error? && !recoverable_error?)`
and `Misc.pid_alive?` short-circuits on `Process.pid == pid`, so an errored
step recorded by this same process is treated as running and silently
skipped on resume.
**Evidence**: `Observation/probe/deploy_skip_canfail_manifest_9b4bddf1c77993983c8b359c279db531.json`
**Recommendation**: Do not treat `Process.pid == pid` as alive for resume
decisions.
**Effort**: Low.

### A19. `Workflow.trace_job_times(fix_gap: true)` crashes

**Location**: `lib/scout/workflow/deployment/trace.rb`
**Issue**: `fix_gap:` calls `Misc.collapse_ranges`, undefined in
scout-essentials 1.9.0, so any caller crashes with `NoMethodError`.
**Evidence**: `Observation/probe/deploy_queue_trace_cli_a4d8ebee4bfb75b92eb236b29d8c214c.json`
**Recommendation**: Vendor the range collapse or drop the option.
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

### M6. `TSV.open` with an absent `key_field` name fails with a bare `TypeError`

**Location**: `lib/scout/tsv/parser.rb:47`
**Issue**: A `key_field:` name missing from the header raises
`TypeError: no implicit conversion from nil to integer`, while the
analogous `fields:` error is descriptive.
**Evidence**: `Observation/probe/tsv_change_id_translate_fdafb76c464ed95d7b9db869cd94b451.json`
**Recommendation**: Validate the key field against the header with a
descriptive error.
**Effort**: Low.

### M7. `TSV.paste_streams` rejects `bar:`

**Location**: `lib/scout/tsv/util.rb` (`paste_streams`)
**Issue**: `paste_streams` raises `ArgumentError` on a `bar:` keyword while
every neighbouring entry point accepts it.
**Evidence**: `Observation/probe/tsv_stream_pipeline_01a787ca0fc21dd87098dc9261d59c08.json`
**Recommendation**: Accept and honour `bar:` like the sibling methods.
**Effort**: Low.

### M8. PackedIndex mask parsing fails late

**Location**: `lib/scout/persist/engine/packed_index.rb`
**Issue**: Unknown or bare codes are not rejected at parse time; they
produce `item_size < 3` and then `ArgumentError: negative argument` in
`initialize` (`@nil_string`).
**Evidence**: `Observation/probe/persist_fwt_pki_surface_7309a411094733c9eb924483055f5f81.json`
**Recommendation**: Validate mask elements at parse time.
**Effort**: Low.

### M9. Engine availability is probed at load time with only a warning

**Location**: `lib/scout/persist/engine.rb`
**Issue**: A missing `tokyocabinet` gem surfaces as a `Log.warn` at load
and then as `NameError`/`NoMethodError` at first use; there is no queryable
availability API.
**Evidence**: `Observation/probe/persist_loader_and_availability_7fe10205065dbf56c91172b820a2c00e.json`
**Recommendation**: Expose an `available_engines` helper and fail fast on
explicit engine requests.
**Effort**: Medium.

### M10. The engine string is not part of the persistence path

**Location**: `lib/scout/persist.rb` (`persistence_path`)
**Issue**: Cache identity is identifier + `:other` options, never the
engine, so switching engines for an existing identifier silently reuses the
previously written file (a format mismatch surfaces as a TokyoCabinet open
error, if at all). Workaround: bump the identifier or an `:other` option.
**Evidence**: `Observation/probe/persist_cache_identity_204e3163af8d74ea0c93b848b54894b2.json`
**Recommendation**: Fold the engine into the path digest, or invalidate on
engine change.
**Effort**: Medium.

### M11. `wait_semaphore` silently recreates a missing name with value 1

**Location**: `lib/scout/semaphore.rb`
**Issue**: A typo'd or unlinked name is indistinguishable from a fresh
semaphore: `wait` logs "appears missing", recreates with value 1 and
retries, so the recreated bound may differ from the original.
**Evidence**: `Observation/probe/wq_semaphore_semantics_da869a640094600c2036d6ce2f793444.json`
**Recommendation**: Add a `strict:` opt-out so stale-name detection is
possible without breaking resilience.
**Effort**: Low.

### M12. `thread_each_on_semaphore` swallows exceptions

**Location**: `lib/scout/semaphore.rb`
**Issue**: It rescues `Exception`, logs, kills the threads and returns the
`Thread` array, so callers get no signal that work was lost (`thread.value`
re-raises, but only if the caller thinks to read it).
**Evidence**: `Observation/probe/wq_semaphore_semantics_da869a640094600c2036d6ce2f793444.json`
**Recommendation**: Re-raise, or return a status-bearing object.
**Effort**: Low.

### M13. `scout workflow example` exits 0 even when every forked example failed

**Location**: `scout_commands/workflow/example`
**Issue**: The command forks and loads rbbt-util's `task` command; on a
scout-only install the child fails before running anything (`ERROR` /
`NO RESULT`) while the parent still exits 0, so the exit status does not
mean "examples passed".
**Evidence**: `Observation/probe/cli_command_smoke_0821acf45703f7a32f99a79b5db6e491.json`
**Recommendation**: Propagate child failures to the exit status.
**Effort**: Low.

### M14. `Entity.formats` negative-cache race can lose a first registration

**Location**: `lib/scout/entity.rb` (`@find_cache`)
**Issue**: A first-time read racing a first-time registration of the same
key can observe the negative-cache entry and lose the update; stable-key
reads are safe.
**Evidence**: `Observation/probe/entity_formats_registry_concurrency_1907f6e5e8bf7cf4ca1af80e698e4b94.json`
**Recommendation**: Clear the negative-cache entry under the same lock as
registration.
**Effort**: Medium.

### M15. `_ary_property_cache` fill is not atomic

**Location**: `lib/scout/entity/property.rb:138`
**Issue**: `container._ary_property_cache[cache_code] ||= ...` runs the
block twice under concurrent cold access, and a container shared across
modules reuses the first module's entry (values stay correct; identity and
block-run counts do not).
**Evidence**: `Observation/probe/entity_ary_property_cache_concurrency_716bc268ff148f3ffc4e269c5b98042b.json`
**Recommendation**: Guard the fill with a per-container mutex and key by
module.
**Effort**: Medium.

### M16. `annotated_array: false` in `Entity.setup` is dead

**Location**: `lib/scout/entity.rb:41`
**Issue**: The guard `! options[:annotated_array] == FalseClass` can never
be true, so arrays are always extended with `AnnotatedArray` and the
documented opt-out does nothing.
**Evidence**: `Observation/probe/entity_prepare_entity_semantics_a9240a17213da91fe1d5d730d242d385.json`
**Recommendation**: Fix the comparison or remove the option.
**Effort**: Low.

### M17. `entity_options:` does not add a `namespace` annotation

**Location**: `lib/scout/entity.rb` (`prepare_entity`)
**Issue**: Passing `entity_options: {namespace: ...}` does not annotate the
resulting entities; namespace must come from the entity module or an
explicit `setup(..., namespace:)`.
**Evidence**: `Observation/probe/entity_prepare_entity_semantics_a9240a17213da91fe1d5d730d242d385.json`
**Recommendation**: Either honour `entity_options` or reject unknown keys.
**Effort**: Low.

### M18. `merge_rules` and `accumulate_rules` disagree

**Location**: `lib/scout/workflow/deployment/orchestrator/rules.rb`
**Issue**: Within one job `merge_rules` is first-wins, while down the
dependency tree `accumulate_rules` is value-aware (max/sum/concat); the same
rule file therefore merges differently depending on where it is applied.
**Evidence**: `Observation/probe/deploy_orchestrator_batches_f4c44982f6d7c03dd352a084c846f448.json`
**Recommendation**: Document one merge algebra and apply it in both places.
**Effort**: Medium.

### M19. `task_cpus`/`cpus` aliasing and nested-`resources` precedence are implicit

**Location**: `lib/scout/workflow/deployment/orchestrator/rules.rb`
**Issue**: `task_cpus` is an undocumented alias accepted for `cpus`, and a
nested `resources:` hash silently wins over top-level `cpus`/`IO`/`mem`;
the precedence is nowhere stated.
**Evidence**: `Observation/probe/deploy_local_end_to_end_a5040fbac4020461dd7802d8fe70f0c0.json`
**Recommendation**: Normalize once and document the precedence order.
**Effort**: Low.

### M20. PBS header generation silently drops most resource options

**Location**: `lib/scout/workflow/deployment/scheduler/` (PBS engine)
**Issue**: The PBS header writer comments out
`task_cpus`/`nodes`/`time`/`constraint`/`exclusive`/`licenses`/`gres`/`mem`/
`mem_per_cpu` instead of emitting them, so requested resources are lost
without any diagnostic.
**Evidence**: `Observation/probe/deploy_scheduler_script_generation_752ae371b1324cf42ac7f70e738ea0a8.json`
**Recommendation**: Emit the options or warn per dropped option.
**Effort**: Medium.

### M21. The `launcher: :srun` default is dead code

**Location**: `lib/scout/workflow/deployment/scheduler/job.rb` (`exec_cmd`)
**Issue**: The guard compares `self.system == :slurm` while engines return
Strings (`"SLURM"`), so the `srun` launcher never fires and the default
`#EXEC_CMD` is plain `scout`.
**Evidence**: `Observation/probe/deploy_scheduler_script_generation_752ae371b1324cf42ac7f70e738ea0a8.json`
**Recommendation**: Normalize the system symbol before comparing.
**Effort**: Low.

### M22. The `env:BATCH_SYSTEM` token is inert

**Location**: `lib/scout/workflow/deployment/scheduler/scheduler.rb`
**Issue**: `env:` resolution applies to *values*, so the
`'env:BATCH_SYSTEM'` option-key token never reads the environment; a nested
`set({'system' => {'batch' => ...}})` hash also does not reach the flat
`system … batch scheduler` key chain.
**Evidence**: `Observation/probe/deploy_env_token_and_batch_dir_a67caef358a1c129d7138e347048f4c4.json`
**Recommendation**: Resolve `env:` on option keys too, or use the
documented flat key.
**Effort**: Low.

### M23. `KnowledgeBase#documentation_markdown` is dead

**Location**: `lib/scout/knowledge_base/description.rb:33-42`
**Issue**: `@libdir` is never assigned (always `nil`, so the method returns
`""`), and if it were set the body would raise `NameError` on the `file`
local.
**Evidence**: `Observation/probe/assoc_kb_description_00d1f4b4caa1ce9ee16d58bc3de652b7.json`
**Recommendation**: Implement or remove.
**Effort**: Low.

### M24. `kb.enrichment` and the rbbt registry API are unreachable

**Location**: `lib/scout/knowledge_base/enrichment.rb`
**Issue**: The file is never required by `knowledge_base.rb` and requires
rbbt internally, so `kb.enrichment` raises `NoMethodError`; the same holds
for `register_index`/`register_organism`.
**Evidence**: `Observation/probe/assoc_kb_lists_desc_d8c20ff5d87149c593c70c77756360d4.json`
**Recommendation**: Require and decouple it, or delete it.
**Effort**: Medium.

### M25. `DATABASE@kb` cannot reach another KnowledgeBase

**Location**: `lib/scout/knowledge_base/traverse.rb`
**Issue**: The Traverser rule syntax suggests cross-kb syndication, but the
lookup goes through locally registered names only and raises
`Repo <name> not found and not registered`; there is no public API to
attach a second kb.
**Evidence**: `Observation/probe/assoc_kb_traverse_c1c50b0facbf9a452a37c5b80fbb0c63.json`
**Recommendation**: Add an attach API or reject the form explicitly.
**Effort**: Medium.

### M26. `Association::Index#subset` silently returns `[]` for an unspecified Hash side

**Location**: `lib/scout/association/index.rb` (`subset`)
**Issue**: A typo'd Hash key (e.g. `:soucre`) leaves that side `nil` and
filters everything out, returning `[]` with no error.
**Evidence**: `Observation/probe/assoc_kb_query_dddb9f3ead06074db7f5ea143b0babdb.json`
**Recommendation**: Reject unknown/nil sides with a descriptive error.
**Effort**: Low.

### M27. `define_entity_modules` accepts only bare constant names

**Location**: `lib/scout/knowledge_base/entity.rb`
**Issue**: A qualified `"Object::Kin"` reaches `Object.const_set` with a
`::` in the name and raises `wrong constant name`; entity keys that are not
valid constant names are unusable. The qualified form is accepted by
`const_get` when the constant exists, so the failure only appears on first
creation.
**Evidence**: `Observation/probe/assoc_kb_identify_fecef406d3b496adb70cd1a918be1a39.json`
**Recommendation**: Split on `::` before `const_set`, or validate the key.
**Effort**: Low.

### M28. `Scout.file_time` clobbers `ctime` for existing files

**Location**: `lib/scout/monitor.rb`
**Issue**: The `info[:ctime] = Time.now - 999` fallback sits outside the
rescue, so an existing file's real `ctime` is overwritten and only
`elapsed` is trustworthy.
**Evidence**: `Observation/probe/wq_monitor_api_1d49045bd529c9b0f9a4e0004e6c1558.json`
**Recommendation**: Move the fallback inside the rescue.
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

### L7. tkrzw coverage is masked as passing

**Location**: `test/scout/persist/engine/test_tkrzw.rb`,
`test/scout/persist/tsv/adapter/test_tkrzw.rb`,
`test/scout/persist/tsv/adapter/test_serialize.rb`
**Issue**: Two of the three files are 0 bytes and the third wraps everything
in `begin/rescue Exception`, so the absent gem reports as a green suite.
**Evidence**: `research/persistence-probes.md` (test-run section)
**Recommendation**: Skip with a message and unskip when the gem is present.
**Effort**: Low.

### L8. No test suite for `lib/scout/monitor.rb`

**Location**: `test/scout/` (missing `test_monitor.rb`)
**Issue**: A public read-only surface with two traps (String dirs, the
`file_time` ctime clobber) and a live bug has no regression test.
**Evidence**: `research/concurrency-probes.md` (§ test coverage)
**Recommendation**: Add a small `test/scout/test_monitor.rb`.
**Effort**: Low.

### L9. Cosmetic help drift in the command surface

**Location**: `scout_commands/system`, five other command files
**Issue**: `system status` prints the header `rbbt system status(1)`
(stale `$0` rewrite) and five commands carry placeholder summaries
(`Description of the tool`, `Queue a job in Marenostrum`, `Run examples`).
**Evidence**: `Observation/probe/cli_command_smoke_0821acf45703f7a32f99a79b5db6e491.json`
**Recommendation**: Derive headers from the real `bin/scout` name and fill
the summaries.
**Effort**: Low.

### L10. `--help` is not understood on a directory word

**Location**: `bin/scout` (dispatcher)
**Issue**: `scout workflow --help` exits 255 ("not understood") because
only command files carry `--help` handling; directory prefixes do not.
**Evidence**: `Observation/probe/cli_command_smoke_0821acf45703f7a32f99a79b5db6e491.json`
**Recommendation**: Add a dispatcher-level help word.
**Effort**: Low.

### L11. `KnowledgeBase#delete_list` carries a dead broken guard

**Location**: `lib/scout/knowledge_base/list.rb:90`
**Issue**: The guard interpolates an undefined `user` variable and its
"raise" is a bare interpolated String; the line is unreachable because
`list_file` raises `List not found <id>` first (list.rb:23), so the
observable behavior is correct.
**Evidence**: `Observation/probe/assoc_kb_lists_e74ff317a5260aa2a8c9a5d879895422.json`
**Recommendation**: Delete the dead guard or raise a proper exception.
**Effort**: Low.

### L12. Dead `RemoteStep` branch in `include_workflow`

**Location**: `lib/scout/workflow/definition.rb:212`
**Issue**: The branch tests a `RemoteStep` class that exists in neither
scout-gear nor scout-camp (remote steps are an annotation on `Step`), so it
is unreachable in this repository.
**Evidence**: `Observation/probe/wf_remote_step_api_1394e816dd91f784261e88f2e2cf89a7.json`
**Recommendation**: Remove the branch.
**Effort**: Low.

### L13. Batch-directory default diverges from the documented layout

**Location**: `lib/scout/workflow/deployment/scheduler/` (`batch_base_dir`)
**Issue**: Batch dirs default to
`~/scout-batch/<SYSTEM>_scout_job-<wf>-<task>-<rand>/` via
`batch_base_dir`/`batch_dir`; `var/<workflow>/batch/...` only arises when
those are set. The doc page was corrected this pass; the default itself
remains surprising.
**Evidence**: `Observation/probe/deploy_env_token_and_batch_dir_a67caef358a1c129d7138e347048f4c4.json`
**Recommendation**: Consider a workflow-relative default or keep and
document the current one prominently.
**Effort**: Low.

## How to use this document

1. Review high-priority items first (H1–H8, A1–A19): they represent
   correctness and architectural concerns that can cause silent
   failures.
2. Consult `research/` artifacts for the underlying evidence; each item
   cites its source location.
3. Track resolution status per item (resolved / partial / won't-fix).
