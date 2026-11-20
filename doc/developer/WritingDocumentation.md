# Writing Scout documentation

Write for someone using this checkout for the first time. A person running a workflow and an agent calling its tools need the same public facts. A contributor changing the implementation needs a different guide.

## Where information belongs

| Reader’s question | Where to answer it |
| --- | --- |
| What does this repository provide? How do I start? | Root `README.md`. Introduce the repository, show first use, and link to user guides. |
| Which tool should I call for this job? | `doc/user/README.md`, the preferred introduction for agents and a useful starting point for people. |
| How do I carry out a particular operation? | A focused guide in `doc/user/`. Include the public API, command or task and a worked example. This includes building workflows with Scout’s public API. |
| What must I understand to change this repository? | `doc/developer/`. Put contributor setup, architecture, extension procedures, implementation rationale and invariants here. |
| What has the current team tried, and what remains? | Temporary working artifacts in the repository. Contributors and agents resuming active work consult them directly. |

Keep phases, rollout status, handoffs, investigation trails and pending work out of durable documentation, including developer guides, task descriptions and input help. A clean checkout must make sense even when every working artifact is absent. Extract any lasting fact and state it in terms the reader can use. For example, “Returns one TSV row per inference” tells a caller what to expect. “Returns the Phase 3 format” requires access to a past conversation.

## Agent introduction

When `doc/user/README.md` exists, agents receive it in place of the root README’s workflow description. The root description is the fallback. Write the introduction so a reader can:

- Recognize the problems this workflow handles and choose among its main operations. Group tasks by intent and name the usual first call.
- Follow one short, representative path from a valid starting input to a recognizable result. If one task’s output feeds another, show what to pass.
- See any prerequisite or limitation that changes the choice of tool. Link directly to a focused user guide for less common cases.

For example, ScoutCoder’s documentation tools can be introduced in two sentences: “To find a guide, call `help_list_repo_documents` with the repository name. Pick a returned identifier and pass it as `document` to `help_get_repo_document` with the same `repo` to read the text.” Use this level of detail for each major use case. A list of links alone leaves the first decision to the reader. Skills are linked to agents automatically; omit skill inventories from both READMEs.

## Repository README and workflow task index

For a library or standalone CLI, introduce its purpose, a minimal invocation and the relevant user guides. Add a task index only for a workflow that exposes tasks.

Scout reads `workflow.md` when supplied and otherwise uses `README.md` for parsed workflow documentation. Edit the file the workflow loads. Put a one-line title first, followed by a blank line. The text before `# Tasks` is the workflow description used in help. Make it useful on its own.

```markdown
A workflow for inspecting example tables.

Use this workflow to check a table before importing it.

# Tasks

## list_columns
List the column names in a TSV file.

Supply the TSV path as `table`. Returns the column names in header order.
```

Use exactly `# Tasks` on its own line and `## task_name` for each public task, spelled as declared. The next level-one heading ends the index. The last task owns all text up to that heading or the end of the file. Inside entries use paragraphs, lists or indented examples. Keep level-one and level-two headings out of example text at the start of a line, even in fenced code.

## Task and input descriptions

Start a task entry with one sentence giving the operation and its result. Add what a caller needs to select and use it: the accepted input, result type and shape, and any consequential side effect or failure condition. For a TSV, say what a row represents and identify its key when callers use it for lookup or as another task’s input.

Write each input description in the task declaration so it works in isolation in generated help. Use the declared name and type. Explain what value to supply, including its namespace, units or format when ambiguous. For optional inputs, give the effective default when it changes behavior. For example, describe `document` as “Document identifier returned by `help_list_repo_documents` for the same repository, e.g. `user/Cookbook.md`.” “Document to retrieve” adds nothing to the name. Use the README for relationships and examples that span inputs.

## CLI documentation

Keep command help and the guide in `doc/user/` consistent. Give the exact invocation, required arguments and one runnable example with its expected output or effect. Explain options and defaults that affect the result. Identify input and output channels (stdin, stdout or files), overwrite behavior and exit status where scripts depend on them. Put argument-parsing internals and contributor instructions in `doc/developer/`.

## Review from a clean checkout

Read the introduction alone and try the representative operation. Check task names, input help, defaults and output shapes against the loaded workflow, and CLI examples against the executable. Update affected entries and links in the same change as the public behavior. Extend the nearest relevant guide before adding another. Follow links using only files available to the reader.
