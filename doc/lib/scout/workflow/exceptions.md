# Exceptions

The Scout `Workflow` module includes a robust system for error detection and exception handling to ensure workflows are safe, reliably executed, and failures are reported clearly.

---

### Exception Hierarchy

The principal custom exception defined within the workflow system is:

```ruby
class TaskNotFound < StandardError; end
```

This error is raised explicitly in several workflow operations when a requested task cannot be found.

---

## When Are Exceptions Raised?

- **Task Lookup**: If a user or program requests a job for a task name that is not part of the workflow, the workflow will raise `TaskNotFound`.

  **Example from tests:**
  ```ruby
  def job(name, *args)
    task = tasks[name]
    raise TaskNotFound, "Task #{name} in #{self.to_s}" if task.nil?
    # ...
  end
  ```

  If you attempt:
  ```ruby
  Baking.job(:unknown_task)
  ```
  you will get:
  ```
  TaskNotFound: Task unknown_task in Baking
  ```

- **Workflow Loading**: When requiring or loading a workflow (via `Workflow.require_workflow`), if the requested workflow cannot be found, an informative error is raised, unless `autoinstall` is enabled and installation succeeds. If installation fails, a load error is reported.

- **Repository and Installation Issues**: When installing workflows, if the repository cannot be found, an error such as `"Workflow repo does not exist: ..."` is raised to alert users to misconfiguration or network problems.

  ```ruby
  raise "Workflow repo does not exist: #{ repo }"
  ```
  This surfaces in cases like a missing repo URL or incorrect workflow name.

- **Configuration & Task Parameter Failures**: Parameter and configuration errors (such as missing inputs) are surfaced promptly with descriptive error messages, ensuring that issues in workflow or task definitions rarely go unnoticed.

---

## Example Usage and Failure Modes

For instance, given the following workflow:
```ruby
module Baking
  extend Workflow
  task :whisk_eggs => :string do ... end
end
```
The call:
```ruby
Baking.job(:muffin_tray)
```
will immediately raise a `TaskNotFound` error.

---

## Test Validations

Edge cases and error behaviors are explicitly validated in the test suite:

- Attempted access to undefined tasks results in `TaskNotFound`.
- Workflow auto-installation falls back gracefully—if cloning fails, a helpful error message is raised.
- Task/job execution failures, dependency errors, or misconfigurations always report exceptions with context.

---

## Summary

Robust exception handling in `Workflow` ensures that:

- Missing tasks and workflows are caught early.
- Repository and install issues are reported with context.
- Parameter and input errors provide prompt, descriptive feedback.
- All exceptions are surfaced both in-program and via the CLI.

This enables resilient, reliable use of workflows across programmatic and command-line/subprocess environments, facilitating both interactive exploration and deployment at scale.