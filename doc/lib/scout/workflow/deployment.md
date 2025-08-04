# Deployment

The `Workflow` module's *Deployment* subsystem provides the mechanisms to register, locate, install, update, and orchestrate workflows and their jobs. It seamlessly integrates with the larger Scout framework, enabling both programmatic and command-line interaction for robust reproducible computation.

## Key Capabilities

- **Automatic Workflow Registration & Discovery:**  
  When a module extends `Workflow`, it is automatically registered and can be discovered, listed, and loaded. Discovery takes workflow names or fully qualified names and finds the appropriate workflow files, looking in `workflow_dir` and falling back to autoinstall if configured.

- **Dynamic Installation and Updating:**  
  Workflows are fetched either from local repositories or remote sources (mainly Git-based), with support for batch and single installation and updates. If a workflow is missing and autoinstall is enabled, it will be cloned from the default or configured repo.  
  *Example (CLI):*  
  Use `scout workflow install Baking` to install or update the `"Baking"` workflow.

- **Directory/Repository Management:**  
  Workflow search and storage locations are determined by environment variables (`SCOUT_WORKFLOW_DIR`, `SCOUT_WORKFLOW_REPO`), config files, or fall back defaults. This ensures workflows are located properly for both system or user-level installation.

- **Job Creation and Task Lookup:**  
  The `job` method on a workflow instance is used to create or locate parameterized jobs:
  ```ruby
  Baking.job(:bake_muffin_tray, "Normal muffin").run
  ```
  If the required workflow is not present, the system attempts auto-installation and retry.

- **Exception Handling:**  
  If an unknown task is requested, a `TaskNotFound` exception is raised, providing clear error feedback for common user errors or misconfiguration.

## Orchestration and Resource Management

The heart of deployment is the job orchestrator (`Workflow::Orchestrator`):

- **Job Orchestration:**  
  Supports dependency resolution, scheduling, parallelization, and resource-capped job execution, as shown in test coverage:
  ```ruby
  orchestrator = Workflow::Orchestrator.new(0.1, "cpus" => 30, "IO" => 10, "size" => 10 )
  orchestrator.process(rules, jobs)
  ```

- **Resource Constraints:**  
  Jobs can request resources (e.g. cpus), and orchestrator ensures the workload does not exceed available system resources. Rules for task resource requirements are read from YAML and respected across all orchestrated jobs.

- **Dependency-aware Scheduling:**  
  The orchestrator walks the job dependency graph, ensuring prerequisites are fulfilled, errors are handled/retried where possible, and jobs released when completed.

- **Tested Parallel Scaling:**  
  In test cases, multiple jobs and dependencies are created, and orchestrator ensures efficient CPU allocation:
  ```ruby
  jobs.concat %w(TEST1 TEST2).collect{|name| TestWF.job(:d, name + " #{i}") }
  orchestrator.process(rules, jobs)
  ```

- **Erasure and Archival:**  
  Rules (YAML) can specify that certain dependencies should be erased after completion for space or provenance management. This is validated in tests by checking if dependencies are removed and their data archived.

## Integration Points

- **Command-line Tools:**  
  The Scout command suite exposes workflow installation and update (`workflow/install`), orchestration, and workflow discovery/use via subcommands.

- **Anonymous Workflow Support:**  
  Test-derived and interactive workflows can be created quickly for ad hoc use:
  ```ruby
  wf = Workflow.annonymous_workflow do
    task :length => :integer do
      self.length
    end
  end
  assert_equal 5, wf.tasks[:length].exec_on("12345")
  ```

- **Production and Provenance:**  
  Jobs can be batch-produced (`Workflow.produce`) with concurrency limits, and provenance is tracked automatically as part of job execution and archive.

## Edge Cases & Robustness

- If the workflow is not present, and autoinstall is true, the installation is retried transparently.
- If resource needs exceed system limits, jobs are held until free capacity exists.
- Errors in job execution are trapped; jobs with recoverable errors are retried (`job.recoverable_error?`); failed jobs release resources.
- If workflow directories/repositories are misconfigured or unreachable, errors are descriptive.

## Examples from Test Coverage

- **Full Orchestration and Erasure:**
  ```ruby
  orchestrator = Workflow::Orchestrator.new(TestWF::MULT, "cpus" => 30, "IO" => 4, "size" => 10 )
  orchestrator.process(rules, jobs)
  jobs.each do |job|
    assert job.step(:c).dependencies.empty?
    assert job.step(:c).info[:archived_info].keys.select{|k| k.include?("TestWF/a/")}.any?
    assert job.step(:c).info[:archived_info].keys.select{|k| k.include?("TestWF/b/")}.any?
  end
  ```

- **Default Handling in Resource Management:**
  ```ruby
  orchestrator = Workflow::Orchestrator.new(TestWF::MULT, "cpus" => 30, "IO" => 4, "size" => 10 )
  orchestrator.process(rules, jobs)
  ```

- **Efficient Parallel Execution:**
  Measurement of CPU allocation and parallel scheduling:
  ```ruby
  assert Misc.mean(second_cpus.values) > 15 
  assert Misc.mean(second_cpus.values) < 30
  ```

- **Provenance and Run Tracing:**
  Jobs and dependencies are tracked fully for both execution and provenance analysis.

## Summary

Deployment in Scout's workflow system is robust, scalable, and automated, from local discovery to remote installation and orchestrated batch execution. Resource, dependency, and error management are all handled with the real-world demands of computational pipelines in mind, as reflected in the comprehensive test-driven idioms and command-line integrations.