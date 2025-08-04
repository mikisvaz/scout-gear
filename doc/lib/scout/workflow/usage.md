# Workflow Usage and Documentation

This page provides a technical overview and practical guide to the usage and documentation mechanisms supported by the `Workflow` framework, as implemented in `scout/workflow/usage.rb`. The Workflow module provides facilities for dynamic introspection, self-documentation, help display and dependency tracing both for workflows as a whole and for their constituent tasks. Below, we describe the API and illustrate how documentation, description strings, input management, usage formatting, and dependency display work, using real test cases and command line tool behaviors.

---

## Workflow and Task Usage Overviews

Workflows and their tasks are richly self-describing. Each can provide concise or detailed help and usage information, automatically generated based on the descriptions, dependencies, and input types defined by the workflow author.

### Workflow-level Usage

Workflows expose a `.usage([task = nil, abridge = false])` method. 

- When invoked with no arguments, the workflow will print a summary documentation, including the title, description, list of tasks, and for each task a short description as well as an indication of dependencies.
- When invoked with a specific task or task name, it prints detailed information regarding just that task.

**Example from tests:**

```ruby
assert_match "evaluate if the documentation", UsageWorkflow.usage
```

Here, `UsageWorkflow.usage` displays workflow-level documentation, confirming that the workflow's description is shown.

When a command line tool (like `scout workflow task ...`) is run with `--help`, it triggers the same usage output for that specific workflow and (optionally) task.

### Task-level Usage

Each Task responds to a `.usage([workflow, deps])` call that summarizes its purpose, expected arguments, dependencies, and return type.

Documentation is based on metadata attached with `desc` and `input` declarations, and includes the following:

- Task title and description (the first paragraph of `desc`)
- A section for each input, with type annotation and longer description 
- Input select options (if any)
- Inputs from dependencies, clearly separated
- Return type
- Notes about argument parsing (arrays, files, etc.) and special conventions

**Tested behaviors:**

```ruby
assert_match /Desc2/, UsageWorkflow.tasks[:step2].usage(UsageWorkflow)
assert_match /--array/, UsageWorkflow.tasks[:step2].usage(UsageWorkflow)
```

This ensures both the task description ("Desc2") and argument help (`--array`) are present.

**Handling fixed/fused inputs from dependencies:**

```ruby
assert_match(/Desc2_fixed/, UsageWorkflow.tasks[:step2_fixed].usage(UsageWorkflow))
refute_match(/--array/, UsageWorkflow.tasks[:step2_fixed].usage(UsageWorkflow))
```

Here, when an input (like `:array`) is fixed via a dependency (`dep :step1, :array => %w(a b)`), it is omitted from the usage string as it is not user-supplied.

### Task Aliases and Usage

Task aliases, created via `task_alias`, are included in the documentation with their respective description:

```ruby
desc 'Desc3'
task_alias :step3, UsageWorkflow, :step2

desc "Desc3"
dep :step3, :array => %w(a b)
task :step3_fixed => :string do
end
```

Tests ensure documentation for aliases and related fixed-input variants are correctly rendered:

```ruby
assert_match(/Desc3/, UsageWorkflow.tasks[:step3].usage(UsageWorkflow))
assert_match(/Desc3/, UsageWorkflow.tasks[:step3_fixed].usage(UsageWorkflow))
```

### Input Type Documentation and Argument Handling

The usage display highlights options of types `:array`, `:file`, and `:tsv`, showing specialized explanation notes:

- **For arrays:** Arguments can be comma-, pipe-, or newline-separated; files and STDIN are supported. The `--array_separator` can customize separators.
- **For files/TSV:** STDIN is accepted via `-`.

### Input Select Options

If an input is a `:select`, all valid choices are listed within the usage section.

### Dependency Inputs

When a task depends on another task that requires inputs, any missing inputs from the dependency are documented under "Inputs from dependencies" in the usage output. If no additional inputs are required (because they are fixed or already present as user-supplied inputs), this section is omitted.

---

## Dependency Tree and Provenance Information

The module supports tracing and visualizing intricate task dependencies via several methods:

- `.dep_tree(task_name)`: Recursively collects dependency steps for a task.
- `.prov_tree(tree, offset, seen)`: Creates a formatted dependency graph tree.
- `.prov_string(tree)`: Returns a compact string indicating dependency sequence.

In workflow usage output, tasks may be annotated with their workflow provenance `->step1`, `->step1;step2`, etc.

---

## SOPT Integration and Command Line Option Extraction

Workflows and tasks define a SOPT string using `.SOPT_str` to present appropriate command line argument structures (shortcuts and types). For instance:

```ruby
assert_match /--array/, UsageWorkflow.tasks[:step2].usage(UsageWorkflow)
```

Automated SOPT string construction ensures all inputs are documented with appropriate command-line switch identifiers.

---

## Command Line Tool Usage Displays

All Scout workflow command-line commands integrate with this documentation system. For example, running:

```sh
scout workflow task <workflow> <task> --help
```

will output the detailed usage for the given workflow and task, reflecting all the metadata and conventions described above, including dynamic input handling, dependencies, and select options, as shown in the test suite.

---

## Best Practices and Edge Cases

- If a task input is fixed via dependency (`dep :other_task, :input => value`), it will no longer appear as a user-supplied input in the usage string.
- Task description formatting is robust: if the description is short, it's used as a task subtitle; if it's long, only the title is displayed inline, with the paragraph following.
- Tasks with no user-supplied inputs clearly say so; tasks with complex dependencies will detail any extra required inputs.
- If there are no tasks or no documentation, helpful fallback strings are shown.
- All of these functionalities are fully tested in integration via the test suite.

---

## Summary

The Workflow usage and documentation system is designed for full transparency and usability, with dynamically generated, context-sensitive documentation for both workflows and tasks. The system captures dependencies, custom input types, select options, aliases, and advanced features, ensuring that end-users and developers alike always have access to accurate, up-to-date, example-driven documentation for any workflow logic.