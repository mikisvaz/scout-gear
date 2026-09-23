# Writing Scout Documentation

This guide is for agents and contributors documenting a Scout repository or
workflow. Documentation is part of the repository interface: it should help a
reader choose the right guide, use the public behavior correctly, and find the
implementation or investigation evidence when needed.

## Documentation locations

Scout repositories use three complementary documentation areas. Keep the
areas distinct rather than placing every note in a single README.

### `doc/user/`

User documentation is normative, task-oriented guidance for people building
or running workflows. Explain the problem being solved, when the feature is
useful, the public API or command, and runnable examples. Prefer concepts and
stable behavior over internal file names. Put workflow authoring, CLI usage,
caching, data processing, and similar how-to material here.

A user guide should normally include:

- a clear title and a short statement of scope;
- the intended audience and when to use the feature;
- core concepts and a minimal working example;
- the normal API or CLI usage, including inputs and outputs;
- common mistakes, limitations, and links to related guides.

Do not present an unverified implementation detail as user-facing behavior.
If behavior is uncertain, probe it or label the statement as a limitation or
open question.

### `doc/developer/`

Developer documentation describes implementation, architecture, extension
points, and invariants needed to change Scout itself. It may name classes,
methods, source files, persistence formats, and lifecycle states. Explain why
the code behaves as it does, not only what a method is called.

A developer guide should identify its audience and usually include the
relevant subsystem map, lifecycle or data flow, source locations, extension
procedure, compatibility concerns, and known issues. Verify source locations
when writing them because implementation details can change.

### `research/`

Research files are non-normative investigation records. Use them for probes,
experiments, competing hypotheses, detailed observations, and conclusions that
are useful but not yet reviewed as stable documentation. Preserve the causal
trail: record the question, commands or tests, observations, interpretation,
uncertainty, and conclusion. Include dates, versions, or environment details
when they affect the result.

Research is evidence for documentation, not a substitute for it. Once a
finding is validated and stable, summarize the supported behavior in the
appropriate `doc/` guide while retaining a link to the research artifact when
its provenance matters. Do not silently turn “not found” into “does not
exist.”

## Choosing and updating documents

Before adding a file, inspect `doc/StartHere.md` and the repository README.
Add a new guide only when the subject has a coherent audience and purpose;
otherwise extend the closest existing guide. Update navigation links in
`doc/StartHere.md` and, when appropriate, the root `README.md`.

Use stable relative links. Keep examples small and executable. Distinguish
observations from claims and hypotheses, especially for behavior discovered
through a probe. If a documentation change depends on an implementation fact,
validate it against source or a clean execution and record the evidence in
`research/` when it is likely to be reused.

## Workflow `README.md` format

A workflow README is both human documentation and a task index consumed by
Scout tooling. It should begin with a one-line description of the workflow,
followed by one or more paragraphs describing its purpose, capabilities,
installation or usage, and important concepts. Headings are allowed in this
introductory section.

The task index must start with a level-one heading on its own line:

    # Tasks

Each task then has a level-two heading containing exactly the task name,
followed immediately by a one-line description. Add one or more paragraphs
with usage, inputs, outputs, dependencies, side effects, examples, or relevant
implementation details:

    ## task_name
    One-line description of what the task does.

    Explain how to use the task, what it returns, and any important caveats.

    ## another_task
    One-line description of the next task.

The task heading must be `## task_name`; do not use additional `#` or `##`
headings inside a task description, because the parser uses headings to find
task boundaries. Use paragraphs, lists, code indentation, or lower-level
formatting that does not create another task heading. Keep task names aligned
with the actual declared tasks and document inputs and return types using the
workflow's public names.

A minimal workflow README therefore has this shape:

    A workflow for transforming examples.

    This workflow provides reusable tasks for ...

    # Tasks

    ## greet
    Greet a supplied name.

    The `name` input is optional and the task returns a string.

When changing a workflow task, update its README entry in the same change.
When adding or removing a task, check the task list against the loaded
workflow, and test examples where practical. The README is a synthesis of
verified workflow behavior; detailed implementation discoveries belong in
`research/` or the developer documentation.

## Review checklist

Before submitting documentation, check:

1. Is the audience clear (`doc/user`, `doc/developer`, or `research`)?
2. Are claims supported by current source, tests, or a cited investigation?
3. Are examples consistent with current APIs and task names?
4. Does `doc/StartHere.md` or the root README need a navigation link?
5. If this is a workflow README, is there one `# Tasks` section and a `##`
   entry for every documented task without nested task headings?
6. Are limitations and uncertainty stated instead of hidden?

For a non-trivial documentation change, preserve the evidence used to resolve
uncertainty in a research note or test output rather than relying on an
uncited transcription.

## See also

- [Start Here](../StartHere.md)
- [Building Workflows](../user/BuildingWorkflows.md)
- [Workflow Engine](WorkflowEngine.md)
- [Workflow README examples](../../README.md)

<!-- ScoutCoder: keep this guide general enough for agents working in any Scout repository; workflow-specific tooling may add stricter checks, but should not replace this baseline format. -->
