# Task Subtopic

The Task subsystem in the Scout Workflow framework forms the atomic unit of computation and orchestration, enabling declarative, reproducible pipelines with explicit input/output validation, dependency linking, and rich step/job management capabilities.

## Task Concept

A “task” is conceptually a method with:
- a name unique within its workflow,
- an input signature (with optional types, defaults, validations),
- possible dependencies on other tasks (within or across workflows),
- an annotated output type,
- Ruby code implementing the computation.

Tasks further enable:
- parameterized job instantiation,
- automatic and override-able dependency injection,
- persistent, uniquely-identified output directories,
- helper function access,
- provenance and reproducibility tracking.

## Task Definition

Tasks are declared in workflow modules with the `task` keyword. Inputs are declared via `input`, and dependencies via `dep`. Inputs, dependencies, and outputs all contribute to the unique identification and cache key of each job.

**Examples from tests:**

Declaring tasks, inputs, and dependencies (see `test_dependencies_jobname_input` in tests):

```ruby
wf = Module.new do
  extend Workflow
  self.name = "TestWF"

  input :name, :string, "Name", nil, jobname: true
  task :step1 => :string do |name|
    name
  end

  dep :step1
  task :step2 => :string do
    step(:step1).load
  end

  dep :step1, jobname: nil
  task :step3 => :string do
    step(:step1).load
  end
end
```

## Task Job Instantiation

A task method does not execute immediately, but can be `.job`-ed to create a persistent workflow “step” (Job). Jobs digest their inputs and resolved dependencies to produce an addressable, cacheable location for execution and result storage. Example (from `test_basic_task`):

```ruby
task = Task.setup do |s=""|
  (self + s).length
end
assert_equal 4, task.exec_on("1234")
assert_equal 6, task.exec_on("1234","56")
```

Or for a real workflow module:

```ruby
job = wf.job(:step2, nil, name: "Name")
assert_equal "Name", job.run
```

## Task Inputs

Inputs can be simple (integers, strings) or complex (arrays, files, paths). They’re specified by order, name, and may have default values, types, and options (such as `jobname: true` for naming). Input assignment validates presence of required fields and matches types:

```ruby
input :input1, :string
task :step1 => :string do |i| i end

dep :step1, :input1 => "1"  do |id,options|
  {:inputs => options}
end
input :input2, :string
task :step2 => :string do |i| step(:step1).load end

job = wf.job(:step2, :input1 => "2")
assert_equal "1", job.run
```

## Dependency Management

Tasks can `dep` on other tasks, optionally mapping or defaulting inputs, and can even be overridden at submission:

```ruby
wf = Workflow.annonymous_workflow do
  input :input1, :integer
  task :step1 => :integer do |i| i end

  dep :step1
  input :input2, :integer, "Integer", 3
  task :step2 => :integer do |i| i * step(:step1).load end
end

step1_job = wf.job(:step1, :input1 => 6)
wf.job(:step2, :input1 => 2, "TaskInputs#step1" => step1_job).exec # == 18
```

This pattern enables fine-grained cache reuse and workflow modularity, including dependency overrides (e.g., for re-running with alternative preprocessing).

## Input/Output Handling and Type Validation

Scout’s task system ensures robust input orchestration with type-aware serialization, hash/digest matching for cache reuse, and full persistence of job provenance. Save/load cycles and digest idempotency are tested, including array and file inputs.

_More info in tests: `test_save_and_load`, `test_digest_file`, etc._

## Job Identity, Provenance, and Replica Control

Each job (or “step”) is uniquely named/digested according to non-default inputs and dependencies. The default is `"Default"`, but alternate IDs and job names can be supplied or auto-derived from inputs, including via `jobname: true` hints—see `test_jobname_input` and `test_jobname_input_reset` for intricate name assignment and provenance cases.

## Exception Handling

Scout’s task engine robustly checks for:
- missing required inputs (raising `ParameterException`),
- incorrect input types,
- missing downstream dependencies (raising `TaskNotFound` or input errors at job time).

## Advanced Patterns

- **Overriding dependency jobs by ID**: Pass a custom job in-place for a dependency with `"Workflow#task" => job`, supporting flexible subgraph recomputation or troubleshooting.
- **Recursive Inputs**: Discover and resolve the full input surface recursively, hiding overridden or fixed parameters to clarify what users need to supply.
- **Block dependencies**: `dep :task, ... do |jobname, options| ... end` yields advanced dynamic dependency resolution and input inference at dependency setup.

## CLI Integration

Tasks, with all their parameterization and dependency logic, are exposed to CLI via `scout workflow task`, supporting serial, queue, and SLURM deployments, input/output (de)serialization, provenance printing, cleaning, and step orchestration. All validated at the test layer for reliability and predictability.

---

For more details and test-driven idioms, consult the test suite (`test/scout/workflow/task/test_task.rb`, `test_inputs.rb`, `test_dependencies.rb`), which covers the nuanced facets of task construction, chaining, input/output logistics, error trapping, CLI/automation, and advanced dependency resolution scenarios.