# Scout Workflow — Definition

The `Workflow::Definition` submodule is the foundation for structurally describing, authoring, and configuring new workflows using a Ruby DSL. This submodule provides the annotation, declaration, and utility methods used to define and connect tasks, helpers, dependencies, and resources within a workflow.

It is essential to the robust management of computational tasks, enabling strong typing, clear descriptions, flexible dependencies, and dynamic task aliases. The test suite highlights idiomatic patterns and edge behaviors.

---

## Main Features

- **DSL for Defining Workflows**
  - Use `helper`, `task`, `input`, `dep`, `desc`, `returns`, and related methods for declaring the full structure of a workflow.
  - Enables helpers for code reuse.
  - Encodes task inputs and outputs with types and documentation.
  - Supports named, parameterizable dependencies across tasks.

- **Dynamic Task Execution and Helper Access**
  - Helpers are callable within tasks and can be invoked directly for modular construction.
  - DSL supports clean task lookup and invocation including dependency navigation (`step(:task_name)`).
  - Tasks can be mapped, exported, or aliased dynamically.

- **Task Alias and Dependency Management**
  - Easily create alias tasks (`task_alias` / `dep_task`) that depend on other task results, with automatic provenance and clean-up control.
  - Fine-grained archiving and clean-up controlled via environment or config (e.g. `SCOUT_FORGET_TASK_ALIAS`, `SCOUT_REMOVE_TASK_ALIAS`), as proven by the test suite.

- **Annotation and Provenance**
  - Description and typing of tasks and inputs (`desc`, `input`, `returns`, `extension`) is systematically recorded and available for documentation generation.

---

## Essential API and Idioms

### Declaring Tasks with Typed Inputs and Outputs

From the test suite:

```ruby
wf = Workflow.annonymous_workflow do
  self.name = "StringLength"
  def self.str_length(s)
    s.length
  end

  input :string, :string
  task :str_length => :integer
end

assert_equal 5, wf.job(:str_length, :string => "12345").run
```
Tasks can be declared with a signature (`:taskname => :output_type`) and an optional block. Inputs are typed and documented using `input`.

### Task Aliases with Parameterization and Dependency Clean-up

Task aliases allow creating new "virtual" tasks that wrap existing logic, optionally fixing parameters.

```ruby
wf = Workflow.annonymous_workflow do
  self.name = "CallName"
  input :name, :string, "Name to call", nil, :jobname => true
  task :call_name => :string do |name|
    "Hi #{name}"
  end

  task_alias :call_miguel, self, :call_name, name: "Miguel"
end

job = wf.job(:call_miguel)
assert_equal "Hi Miguel", job.run
```

**Advanced clean-up behaviors** are configurable:

```ruby
old_cache = Scout::Config::CACHE.dup
Scout::Config.set({:forget_dep_tasks => true, :remove_dep_tasks => true}, 'task:CallName#call_miguel') 
job = wf.job(:call_miguel)
dep_path = job.step(:call_name).path
job.run
refute job.dependencies.any?
refute Open.exist?(dep_path)
Scout::Config::CACHE.replace old_cache
assert_include job.archived_info, dep_path
assert_equal :done, job.archived_info[dep_path][:status].to_sym
```
This mechanism ensures that dependent job artifacts are optionally forgotten or removed, archiving provenance as required for reproducibility.

### Inputs, Dependencies, and Task Chaining

Composite tasks use `dep` to declare task dependencies and access them via steps:

```ruby
wf = Workflow.annonymous_workflow do
  self.name = "CallName"

  task :salute => :string do |name|
    "Hi"
  end

  dep :salute
  input :name, :string, "Name to call", nil, :jobname => true
  task :call_name => :string do |name|
    "#{step(:salute).load} #{name}"
  end

  task_alias :call_miguel, self, :call_name, name: "Miguel"
end
```

This enables deep composition and orchestration of complex routines.

### Helper Methods

Declare reusable code fragments with `helper`:

```ruby
helper :whisk do |eggs|
  "Whisking eggs from #{eggs}"
end
```

Helpers are available in tasks and for interactive access.

---

## Advanced Configuration

- **Directory Assignment**: Override per-workflow job storage or cache directory with `directory=`.
- **Extension and Return Typing**: Customize default file formats or serialization via `extension` and `returns`.
- **Input Expansion**: Use the `input` method with advanced parameters (`:jobname => true`) to alter argument binding and job identification.
- **Export Stubs**: Methods such as `export_synchronous`, `export_asynchronous`, etc. are provided for future or plugin expansion of export logic.

---

## Edge Case and Robustness

- Missing helpers are trapped with a clear exception and message.
- Task aliasing supports both shallow and recursive dependency removal, and partial task preservation as shown in tests.
- Workflow-level configuration and environment variables enable scriptable and testable deployment pipelines.

---

## Summary

The `Workflow::Definition` submodule provides a comprehensive and highly extensible DSL and runtime for describing structured, typed, and self-documented tasks, helpers, and orchestration patterns. The test suite rigorously exercises task signatures, parameter passing, aliasing, dependency management, provenance, and advanced cleanup for robust and reproducible computational workflows in the Scout ecosystem.