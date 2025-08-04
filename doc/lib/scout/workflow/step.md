# Step

The `Step` class in the Scout Workflow system encapsulates a single, parameterized execution of a task within a workflow. A Step instance holds its own state, inputs, dependencies, metadata (including provenance), and provides facilities to orchestrate, persist, fork, stream, and manage job execution. Steps serve as the "job" abstraction that underpins all reproducible workflow execution and provenance in Scout.

---

## Responsibilities and Features

- **Instantiation & Inputs:** Steps are created via the workflow's `.job` API or directly, encapsulating a specific invocation of a task with its resolved arguments and dependency graph.
- **State Management:** Each step has an associated persistent info structure, tracking status (`:setup`, `:start`, `:done`, `:error`, `:aborted`), timestamps, provided inputs, exceptions, and messages.
- **Dependency Handling:** Steps may depend on the results of other steps, recursively managing complex dependency graphs, supporting recursive cleaning, priority input resolution, and can gracefully handle failed or streaming dependencies.
- **Job Orchestration:** Steps can be executed in a variety of modes: locally, in parallel (`fork`), with semaphores, or in batch/queue-based systems.
- **Streaming Support:** Steps natively support streaming large results, with robust IPC and consumption logic. Streaming can be toggled or detected depending on the execution context.
- **Resource and File Management:** Each step tracks its result files, persistent info, and related resources. Offers APIs for archiving inputs, managing associated files, symlink handling, and packaging bundles.
- **Provenance & Info Reporting:** Rich provenance is available for every step, supporting CLI and programmatic info, recursive input collection, direct inspection and reporting, and exception fingerprinting.
- **Process Children:** Steps can spawn/fork child processes, with PID tracking, and provide facilities for robust command execution with child state reporting.
- **Config & Context Integration:** Step execution context can be altered by persistent or workflow-level configuration tokens with deep context merging.

## Example Usage from Tests

**Basic Step Execution:**
```ruby
step = Step.new tmpfile, ["12"] do |s|
  s.length
end
step.type = :integer

assert_equal 2, step.run
```

**Dependency Composition and Recursion:**
```ruby
tmpfile = tmpdir.test_step
step1 = Step.new tmpfile.step1, ["12"] do |s|
  s.length
end

step2 = Step.new tmpfile.step2 do 
  step1 = dependencies.first
  step1.inputs.first + " has " + step1.load.to_s + " characters"
end

step2.dependencies = [step1]

assert_equal "12 has 2 characters", step2.run
```

**Streaming and Parallel Execution:**
```ruby
step1 = Step.new tmpfile.step1, [times, sleep] do |times,sleep|
  Open.open_pipe do |sin|
    times.times do |i|
      sin.puts "line-#{i}"
      sleep sleep
    end
  end
end
step1.type = :array

res = step1.run(true)
assert IO === res
step1.join
```

**Archival and Input Merging:**
```ruby
job = m.job(:step2, option1: "Option1", option2: "Option2")
job.run
job.archive_deps
assert_include job.archived_info, job.step(:step1).path
assert_equal :done, job.archived_info[job.step(:step1).path][:status]
assert_equal "Option1", job.archived_inputs[:option1]
assert_equal "Option1", job.inputs.concat(job.archived_inputs)[:option1]
```

**Recursive Inputs and Overriding:**
```ruby
step1 = Step.new tmpfile.step1, NamedArray.setup(["1"], %w(input1)) do |s|
  s.length
end
step2 = Step.new tmpfile.step2, NamedArray.setup(["2"], %w(input1)) do |times|
  step1 = dependencies.first
  (step1.inputs.first + " has " + step1.load.to_s + " characters") * times
end
step3 = Step.new tmpfile.step2, NamedArray.setup([], %w()) do |times|
  step1 = dependencies.first
  (step1.inputs.first + " has " + step1.load.to_s + " characters") * times
end

step2.dependencies = [step1]
step3.dependencies = [step1, step2]

assert_equal "2", step2.inputs["input1"]
assert_equal "2", step2.recursive_inputs["input1"]
assert_equal "1", step3.recursive_inputs["input1"]
```

**Forked/Child Job Example:**
```ruby
step = Step.new tmpfile, ["12"] do |s|
  pid = child do 
    Open.write(self.file(:somefile), 'TEST')
  end
  Process.waitpid pid
  s.length
end
step.type = :integer

assert_equal 2, step.run
assert_equal 1, step.info[:children_pids].length
assert_include step.files, 'somefile'
```

## CLI and Provenance Exploration

Scout's CLI can operate directly on step/job files:
- `scout workflow info <step_path>` prints step info, inputs, and recursive inputs.
- `scout workflow prov <step_path>` prints a colorized provenance tree, with input/output annotations and dep status.

**Provenance from Test:**
```ruby
step2.run
assert_include Step.prov_report(step2), 'step1'
assert_include Step.prov_report(step2), 'step2'
```

## Robustness and Edge Cases

- Steps can handle failed child processes, with robust exception marshalling.
- Supports cleaning of jobs and recursive dependencies.
- Auto-relocation logic lets Step objects find their backing files even after directory moves.
- Priority and merging logic determines which inputs are used when both direct and recursive dependencies supply values.
- Explicit handling for streaming results, including `SCOUT_NO_STREAM` override.
- Job status is validated with both file presence and process liveness.

## Test-Inspired Defensive Idioms

- **Overriding:** Steps can be overridden via `task_alias`, with diagnostic support for overridden dependencies.
- **Streaming Dependencies:** Steps detect if dependencies are streaming (versus persisted) and adjust orchestration accordingly.
- **Fork/Semaphore:** Steps can execute with concurrency control using named semaphores for resource management.

## File Structure

- All step logic is defined in `lib/scout/workflow/step.rb` and its associated extensions.
- Individual behavioral concerns (info, provenance, status, dependencies, progress, archiving, etc.) are modularized for clarity.

---

For further details, see CLI examples such as `scout workflow info`, `scout workflow prov`, and test suites like `test/scout/workflow/step/test_step.rb`, which showcases streaming, child process management, dependency trees, step forking, cleaning, and comprehensive error edge cases.