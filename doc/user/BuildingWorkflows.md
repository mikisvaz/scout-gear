# Building Workflows

This document explains how to build computational pipelines using the
scout-gear workflow engine. It covers defining tasks, declaring inputs,
specifying dependencies, creating jobs, and running them.

It is intended for workflow authors and application developers who want to
automate multi-step computations.

## What problem does this solve?

A workflow is a graph of computational tasks with dependencies. You need
to define what each task does, what inputs it requires, what it depends on,
and how results are stored. Without a framework, you end up writing custom
scripts for dependency resolution, result caching, provenance tracking, and
error handling.

The scout-gear workflow engine handles all of this declaratively. You define
tasks with a Ruby DSL, declare their dependencies, and the engine resolves
the dependency graph, runs tasks in the right order, streams results
between tasks, persists outputs, and tracks full provenance.

## When do I use it?

- When you have a multi-step computation where later steps depend on
  earlier results.
- When you want automatic caching and re-computation only when inputs
  change.
- When you need provenance tracking (what ran, when, with what inputs).
- When you want to deploy to HPC clusters (SLURM, PBS, LSF) or containers
  (Singularity).

## Core concepts

### Workflow

A workflow is a Ruby module that extends `Workflow`. It groups related
tasks and provides a namespace for job storage.

```ruby
module Baking
  extend Workflow
  self.name = "Baking"

  helper :mix do |a, b|
    "Mixing #{a} and #{b}"
  end
end
```

### Task

A task is a named unit of computation. It declares its inputs, return
type, and dependencies, and provides a block that does the work.

```ruby
task :mix_ingredients => :tsv do
  flour = input[:flour]
  sugar = input[:sugar]
  TSV.setup({ "mix" => [mix(flour, sugar)] }, type: :list, key_field: "Product", fields: ["Description"])
end
```

### Job (Step)

A job is a concrete instance of a task with specific input values. Jobs
are created by calling `.job` on the workflow:

```ruby
job = Baking.job(:mix_ingredients, flour: "100g", sugar: "50g")
```

Each job has a unique path derived from its inputs, so results are cached
automatically. Running the same job twice returns the cached result
without re-executing.

### Dependency

A dependency is another job that must complete before this task can run.
Dependencies are declared with `dep`:

```ruby
dep :mix_ingredients
task :bake => :string do
  mix = step(:mix_ingredients).load
  "Baked #{mix}"
end
```

## Defining a workflow

### Inputs

Declare inputs before a task using `input`:

```ruby
input :flour, :integer, "Grams of flour", 100
input :sugar, :integer, "Grams of sugar", 50
task :recipe => :string do
  "Using #{input[:flour]}g flour and #{input[:sugar]}g sugar"
end
```

Supported input types: `:string`, `:integer`, `:float`, `:boolean`,
`:tsv`, `:array`, `:file`, `:select` (with options).

### Return types

Declare what a task returns with `returns`:

```ruby
returns :tsv
task :process => :tsv do
  # Must return a TSV
end
```

### Helpers

Define reusable methods with `helper`. Helpers are available inside task
bodies as regular method calls:

```ruby
helper :normalize do |values|
  sum = values.map(&:to_f).sum
  values.map { |v| v.to_f / sum }
end

task :proportions => :array do
  normalize([1, 2, 3])
end
```

### Extensions

Set the file extension for results:

```ruby
extension :csv
task :export => :tsv do
  # Result file will be named <digest>.csv
end
```

## Dependencies

### Simple dependencies

```ruby
dep :step_one
dep :step_two
task :combine => :tsv do
  one = step(:step_one).load
  two = step(:step_two).load
  # Combine one and two
end
```

Access dependency results via `step(:name)` inside the task body. The
returned object is a Step; call `.load` to get the result, or `.path` to
get the file path.

### Dependencies from other workflows

```ruby
dep OtherWorkflow, :some_task
task :use_other => :tsv do
  other_result = step(:some_task).load
  # ...
end
```

### Dynamic dependencies

Use a block to decide dependencies at runtime:

```ruby
dep do |inputname, inputs|
  if inputs[:use_fast]
    FastWorkflow.job(:compute, input: inputs[:data])
  else
    AccurateWorkflow.job(:compute, input: inputs[:data])
  end
end
task :analyze => :tsv do
  # The dynamically resolved dependency is available
end
```

### Dependency options

Control how dependencies are computed:

```ruby
dep :risky, compute: :canfail    # Don't fail this task if dependency fails
dep :large, compute: :produce    # Only produce (don't load into memory)
dep :streaming, compute: :stream # Force streaming
```

## Creating and running jobs

### Creating a job

```ruby
job = MyWorkflow.job(:task_name, "job_id", input_one: "value", input_two: 42)
```

- The first argument is the task name.
- The second (optional) argument is the job ID (defaults to "Default").
- The keyword arguments are the input values.

### Running a job

```ruby
# Run synchronously
job.run

# Run and get the result
result = job.run.load

# Produce (compute and persist, without loading the result)
job.produce

# Run in a forked process
job.fork
job.join

# Force streaming
job.run(true)  # true = stream
```

### Checking status

```ruby
job.done?       # Has the result been computed?
job.running?    # Is it currently running?
job.error?      # Did it raise an error?
job.aborted?    # Was it aborted?
job.updated?    # Is the result newer than all dependencies?
```

### Cleaning (re-running)

```ruby
job.clean              # Remove result, info, and files for this job
job.recursive_clean    # Also clean all dependencies
```

## Result persistence

Every job result is persisted to disk automatically. The path follows a
convention:

```
var/jobs/<Workflow>/<task>/<digest>.<ext>
```

The digest is computed from the job's inputs and dependency signatures.
If you run the same job again with the same inputs, the cached result is
returned. If inputs change, a new path is generated.

### Provenance (info file)

Each job has a `.info` sidecar file recording:

- Status (waiting, done, error, aborted, etc.)
- Timestamps (issued, start, end)
- Process ID and hostname
- Inputs and their values
- Dependencies and their paths
- Exception details (if an error occurred)
- Log messages

### Auxiliary files

Jobs that produce files (not just single result files) store them in a
`.files/` directory next to the result file. Use the `file` method inside
a task:

```ruby
task :multi_output => :file do
  f = file("extra_data.txt")
  File.write(f, "some data")
  # The result path is the main output; extra_data.txt is in .files/
end
```

## Including workflows

Merge another workflow's tasks and helpers:

```ruby
module Combined
  extend Workflow
  self.name = "Combined"

  include_workflow FirstWorkflow
  include_workflow SecondWorkflow
end
```

## Running on HPC clusters

The workflow engine supports deployment to SLURM, PBS, and LSF schedulers,
with optional Singularity container isolation.

```ruby
The `produce` method submits jobs to the cluster using scheduler rules.
```

Where `rules` is a hash specifying resource requirements (time, memory,
CPUs, queue, container settings, etc.) per task or workflow.

For details on batch configuration, see the developer documentation on the
[Workflow Engine](../developer/WorkflowEngine.md).

## Common patterns

### Pass-through tasks (aliases)

Create a task that simply forwards a dependency's result:

```ruby
dep :upstream_task
task_alias :downstream_view
```

### Task that depends on all upstream results

```ruby
dep :step_a
dep :step_b
dep :step_c
task :merge_all => :tsv do
  a = step(:step_a).load
  b = step(:step_b).load
  c = step(:step_c).load
  TSV.merge([a, b, c])
end
```

## Common mistakes

- **Forgetting `.load`**: `step(:name)` returns a Step object, not the
  result. Call `.load` (or `.path` for the file path).
- **Using `task` before declaring inputs**: `input`, `desc`, `dep`, and
  `returns` must be called before the `task` definition.
- **Expecting cached results after code changes**: If you change the task
  block code, the old cached result is still used because the path is
  derived from inputs, not code. Use `job.clean` to force re-execution.
- **Passing non-serializable objects as inputs**: Job inputs are serialized
  for the info file. Avoid Procs, file handles, or other non-serializable
  objects.
- **Not handling streaming dependencies**: By default, dependencies stream
  their results. If your task reads the dependency result multiple times,
  call `.load` to materialize it first.

## See also

- [scout-essentials: Annotating Data](https://github.com/mikisvaz/scout-essentials/blob/main/doc/user/AnnotatingData.md)
- [scout-essentials: Caching Results](https://github.com/mikisvaz/scout-essentials/blob/main/doc/user/CachingResults.md)
- [Processing Tabular Data](ProcessingTabularData.md)
- [Caching Data](CachingData.md)
- [Cookbook](Cookbook.md)
