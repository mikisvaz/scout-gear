# Scout Workflow Module

The `Workflow` module serves as the backbone of the Scout framework, providing an extensible system for defining, discovering, installing, documenting, deploying, and orchestrating computational workflows. Workflows are organized into modular tasks, with robust facilities for parameterized execution, dependency management, documentation, provenance, and reproducible analysis across diverse environments.

---

## Table of Contents

- [Definition](#definition)
- [Deployment](#deployment)
- [Documentation](#documentation)
- [Entity](#entity)
- [Exceptions](#exceptions)
- [Export](#export)
- [Path](#path)
- [Persist](#persist)
- [Step](#step)
- [Task](#task)
- [Usage](#usage)
- [Util](#util)

---

## Definition

The `Workflow` module provides the foundation for describing, loading, managing, and running computational workflows in the Scout framework. Workflows are typically defined as Ruby modules, extending `Workflow`, and using DSL methods like `helper`, `task`, `dep`, and `input`.

**Key Features:**

- Workflow discovery, tracking, and management, including automatic installation and updating from repositories.
- Task declaration with typed inputs, dependencies, outputs, and execution as reusable jobs.
- Automatic job caching for efficiency.
- Directory/repository auto-discovery and configuration using environment variables and fallback configs.

**Basic Usage Example:**

```ruby
module Baking
  extend Workflow

  helper :whisk do |eggs|
    "Whisking eggs from #{eggs}"
  end

  task :whisk_eggs => :string do
    whisk(Pantry.eggs.produce)
  end
end

Baking.job(:bake_muffin_tray, "Normal muffin").run
```

**Workflow Loading:**

```ruby
wf = Workflow.require_workflow("Baking")
```

**Edge Cases:**

- If a required workflow is not present, Scout can auto-install it from a registered repository if `autoinstall` is enabled.
- Task lookup or execution for non-existent tasks yields `TaskNotFound`.

## Deployment

The `Workflow` module facilitates workflow registration, auto-discovery, localization, installation, and update. Workflows can be sourced dynamically from local directories or remote repositories, with logic for fallbacks, naming conventions, and Git-based installation.

**Usage Highlights:**
```ruby
wf = Workflow.require_workflow "Baking"
Baking.job(:bake_muffin_tray, "Normal muffin").run
```

- Supports batch installation and update via the command line.
- Directory/repository behavior is customizable with environment variables or config files.
- Job creation and lookup are robustly handled, with explicit exceptions for missing tasks.

### Test-proven idioms:
```ruby
wf = Workflow.annonymous_workflow do
  task :length => :integer do
    self.length
  end
end
assert_equal 5, wf.tasks[:length].exec_on("12345")
```

## Documentation

`Workflow` delivers self-documenting workflows and tasks. Configuration is via environment variables or config files for directories and repositories. Workflows are registered on extension, and documentation is accessible programmatically or through CLI.

**Task and Helper Example:**
```ruby
module Baking
  extend Workflow

  helper :whisk do |eggs|
    "Whisking eggs from #{eggs}"
  end

  task :whisk_eggs => :string do
    whisk(Pantry.eggs.produce)
  end
end
Baking.job(:whisk_eggs).run
```

**Loading/Requiring:**
```ruby
wf = Workflow.require_workflow("Baking")
```

**Edge Cases:**

- If a workflow is missing and `autoinstall` is enabled, Scout attempts Git installation.
- Clear error feedback for missing tasks/workflows.

## Entity

The core `Workflow` module enables:

- Registration of extended modules as workflows, with linked libraries.
- Management of parameterized tasks, steps, and workflow state.
- Facilities for requiring, auto-installing, updating, and loading workflow code.
- Integration with resources for flexible data management.

**Usage Patterns:**

Anonymous workflow example:
```ruby
wf = Workflow.annonymous_workflow do
  task :length => :integer do
    self.length
  end
end
assert_equal 5, wf.tasks[:length].exec_on("12345")
```
Or, for a more typical workflow:
```ruby
assert_equal "Baking batter (Mixing ...)", Baking.job(:bake_muffin_tray, "Normal muffin").run
```

## Exceptions

- Central registry: `workflows`, `workflow_dir`, and `workflow_repo`.
- Workflows are loaded/installed as needed, with descriptive errors if unavailable and `autoinstall` is off.
- Parameter issues, unknown tasks, or misconfigured workflows are rejected early with robust exceptions.

**Illustrative Example:**
```ruby
module Baking
  extend Workflow
  # ...tasks and helpers...
end

Baking.job(:bake_muffin_tray, "Normal muffin").run
```
Raises `TaskNotFound` if the task was not declared.

## Export

`Workflow` enables:

- Discovery, installation, documentation, and execution of computation workflows.
- Encapsulation of jobs as persistent, reproducible Steps.
- Helper method support, tight resource integration, and job caching for re-use.

**Example:**
```ruby
module Baking
  extend Workflow
  # ...helpers and tasks...
end

assert_equal "...", Baking.job(:bake_muffin_tray, "Normal muffin").run
```

**CLI Integration:** Tools allow listing, installation, task execution, provenance inquiry, and info presentation.

## Path

**Responsibilities:**

- Manages where workflows are located/discovered (`workflow_dir`), supports repo cloning and update, and recognizes workflow file patterns.
- Robust to directory, naming, and deployment edge cases.
- Combines flexible task definition and job instantiation with persistent resource paths and provenance.

**Example:**
```ruby
module Baking
  extend Workflow
  # ...helpers and tasks...
end
Baking.directory = tmpdir.var.jobs.baking.find
```

Command-line utilities (`scout workflow list`, `install`, etc.) operate through these conventions.

## Persist

- **Workflow state persistence:** Each job/step includes an info structure with status, timestamps, inputs, dependencies, results, and exception states.
- **Reproducibility:** Inputs, outputs, and provenance are captured.
- **Anonymous workflows:** Rapid creation for ad hoc tasks.

**Example:**
```ruby
wf = Workflow.annonymous_workflow do
  task :length => :integer do
    self.length
  end
end
assert_equal 5, wf.tasks[:length].exec_on("12345")
```

## Step

Steps (jobs) are parameterized instances of tasks, including their input, result (if run), provenance, and status.

**Key features:**
- Helper invocation.
- Dependency resolution (`step(:dependency)`) and result loading.
- Job orchestration and deployment (serial, parallel, queue, SLURM, etc.).
- Persistent metadata.

**Example:**
```ruby
module Baking
  extend Workflow
  helper :whisk do |eggs| ... end
  # ...
end
Baking.job(:bake_muffin_tray, "Normal muffin").run
```

Anonymous workflow execution:
```ruby
wf = Workflow.annonymous_workflow do
  task :length => :integer do self.length end
end
assert_equal 5, wf.tasks[:length].exec_on("12345")
```

Error handling is robust: missing tasks, failed installation, or dependency problems are caught early and explained.

## Task

Tasks define atomic computational units, possibly with dependencies and helpers, strongly integrated with provenance and caching.

- **Task creation** via the `task` keyword, with input/output typing and parameter validation.
- **Dependencies** described with `dep`; helpers shared via `helper`.
- Each job is a persistent Step.

**Example:**
```ruby
module Baking
  extend Workflow

  helper :whisk do |eggs| ... end

  dep :prepare_batter
  task :bake_muffin_tray => :string do |...| ... end

  # ...
end

Baking.job(:bake_muffin_tray, "Normal muffin").run
```

## Usage

The `Workflow` system supports detailed self-documentation and usage display for both workflows and tasks. Automated help strings, generated from `desc`, `input`, `task_alias`, and dependency info, are always available.

**Key API:**
- `.usage([task = nil, abridge = false])`: Summary or per-task documentation, including inputs, types, dependency trees, select options, and special argument handling.
- Dependency display: usage output visually annotates tasks with provenance (e.g., `->step1;step2`).
- Task description formatting auto-adapts based on supplied docstrings.
- Edges/corner cases: dependency-fixed inputs are hidden from documentation, tasks with no user-required inputs say so, etc.

**Example:**
```ruby
assert_match "evaluate if the documentation", UsageWorkflow.usage
assert_match /Desc2/, UsageWorkflow.tasks[:step2].usage(UsageWorkflow)
assert_match /--array/, UsageWorkflow.tasks[:step2].usage(UsageWorkflow)
```

Task aliases and complex input structures are also supported and well-documented.

## Util

`Workflow` exposes a suite of utilities and conventions:

- **Automatic management** of workflow installations, cache control, and result fetching.
- **Helper and task definition** via succinct DSL.
- **Flexible directory and repository configuration**.
- **Extension setup**: when new modules extend `Workflow`, they're automatically registered and linked.
- **Error reporting:** robust to missing workflows/tasks, with clear fallbacks and install logic.

**Common idiom:**
```ruby
module Baking
  extend Workflow

  helper :whisk do |eggs| ... end
  task :whisk_eggs => :string do ... end
end
Baking.job(:whisk_eggs).run
```

Workflow behaviors are surfaced to both Ruby scripts and the Scout CLI.

---

For advanced details and CLI commands, see the subtopics on [definition](#definition), [deployment](#deployment), [documentation](#documentation), [entity](#entity), [exceptions](#exceptions), [export](#export), [path](#path), [persist](#persist), [step](#step), [task](#task), [usage](#usage), and [util](#util).



---

**References:**

See also the full test suite (`test/scout/test_workflow.rb`) for live examples and idioms:
- Modular workflow definition (with and without resources)
- Helpers, tasks, and job chaining
- Robust error handling and edge-case behavior
- Complete CLI integration for running, deploying, updating, and inspecting workflows.