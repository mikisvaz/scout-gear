# Util

The `Workflow::Util` submodule supplies utility methods for constructing, inspecting, and operating on workflows in the Scout environment. It supports the central pattern of defining, discovering, and temporarily creating workflows, as well as dependency querying and installed workflow enumeration.

## Features

- **Anonymous Workflow Construction**: Rapidly build unnamed, ad-hoc workflows for dynamic tasks/testing.
- **Installed Workflow Discovery**: Enumerate all available (installed) workflows for scripting or CLI presentation.
- **Dependency Scanning**: Query within a workflow’s internal dependencies.

## Key Methods

### `Workflow.annonymous_workflow(name = nil, &block)`

Creates and returns a new anonymous workflow module. Optionally, names and roots the workflow for path resolution, then evaluates the definition block within the new module context.

**Test Example:**
```ruby
wf = Workflow.annonymous_workflow "TEST" do
  task :length => :integer do
    self.length
  end
end
bindings = "12345"
assert_equal 5, wf.tasks[:length].exec_on(bindings)
```
This demonstrates creating an on-the-fly workflow with a single integer-typed task and evaluating that task against a String input.

### `Workflow.installed_workflows`

Discovers all installed workflows in the workflows directory, returning a unique array of names.

### `find_in_dependencies(name, dependencies)`

Searches a dependencies array for those matching a specified task name (by symbol), returning all matches.

## Usage Highlights

- Anonymous workflows are especially useful for dynamic scripting, testing, or runtime prototyping of tasks, as demonstrated in the test above.
- Installed workflow listing drives CLI utilities such as `workflow list`.
- Internal dependency search is foundational for provenance and scheduling logic.

## Robustness

- If you use `annonymous_workflow` and specify a `name`, the workflow's directory is resolved and integrated.
- All query utilities are safe for empty/edge-case input (e.g., empty dependencies list).

## Integration

- The methods in `Workflow::Util` are used extensively in both programmatic and CLI access patterns throughout the Scout workflow system, ensuring modularity, succinctness, and code clarity.

See also:  
- [Definition](definition.md) for authoring reusable workflows
- [Task](task.md) and [Step](step.md) for execution idioms
- [Usage](usage.md) for UI/CLI invocation patterns