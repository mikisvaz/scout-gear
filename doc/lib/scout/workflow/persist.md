# Persist

The `persist` facility in the `Workflow` module provides persistent storage and robust provenance for jobs (called Steps) in a workflow. This persistence is essential for reproducibility, status management, information tracking, and practical deployment across computational environments and resource managers.

## Overview

Each workflow can persist its jobs and the resulting state, using the `persist` method. This enables:

- Persistent job and input/output storage for each step.
- Automated selection of a persistent directory (defaulting to a standardized workflow info path, or as configured).
- Consistent serialization and deserialization.
- Job info tracking—including status, timestamps, inputs, dependencies, results, and exception states.

```ruby
def persist(name, type = :serializer, options = {}, &block)
  options = IndiferentHash.add_defaults options, dir: Scout.var.workflows[self.name].persist
  Persist.persist(name, type, options, &block)
end
```

## Default Directory Structure

By default, persisted job data is placed under
```
Scout.var.workflows[<workflow-name>].persist
```
This ensures all steps for a workflow are organized and accessible for command-line tools and provenance tracking.

## Reproducibility and Metadata

Persistent storage lets you:

- Capture all inputs and outputs.
- Store a rich info structure for each job, including exceptions and provenance.
- Enable rapid rescoring, updating, or result querying without recomputation, even after interruptions.

## CLI Integration

Persisted info is surfaced to the command-line via tools such as:
- `scout workflow info`: Inspects and prints all step/job metadata.
- `scout workflow prov`: Recursively traverses and visualizes all dependency/provenance links among jobs, based on persisted info.
- `scout workflow write_info`: Adds, updates, or removes metadata fields across all jobs recursively.

For example, viewing job info:
```
$ scout workflow info some/job/path --inputs
```
or tracing provenance:
```
$ scout workflow prov some/job/path --plot output.png
```

## Test Suite Demonstration

The persist layer is foundational for tests like:

```ruby
assert_equal "Baking batter (Mixing base (Whisking eggs from share/pantry/eggs) with mixer (share/pantry/flour))",
  Baking.job(:bake_muffin_tray, "Normal muffin").run
```

Here, every step and intermediate dependency is stored, enabling both CLI and programmatic access to all metadata and results post hoc.

## Summary

- **Persistent storage is automatic and project-structured.**
- **CLI tools and API surface all metadata, ensuring reproducibility and traceability.**
- **Flexible storage adapters are supported by type and options.**

The persistent workflow storage mechanism is integral to the Scout framework. Every step, its provenance, status, and result, remains accessible for inspection, debugging, update, or re-use, ensuring scientific rigor and operational robustness in workflow development and execution.