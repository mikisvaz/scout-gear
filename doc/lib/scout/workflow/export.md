# Export in the Workflow Module

The `Workflow::Export` system provides a robust mechanism for controlling which tasks and actions are externally accessible (exported) from a workflow. This is critical for defining the public interface of a workflow, managing what operations can be invoked from outside (such as CLI invocation, remote execution, or orchestration), and specifying their execution semantics (asynchronous, synchronous, streamed, or direct exec).

This mechanism is an integral part of the reproducibility and automation model of Scout workflows, supporting clarity and security in API exposure.

---

## Types of Exports

- **Asynchronous Exports:** Tasks that can be run asynchronously, suitable for remote queueing, parallel execution, or offloaded deployments.
- **Synchronous Exports:** Tasks intended for direct, blocking execution, such as status queries, helper utilities, or information access.
- **Exec Exports:** Tasks that are invoked as direct computation jobs, usually with tracked output and provenance.
- **Stream Exports:** Tasks whose output is streamed directly, allowing real-time or progressive consumption by callers.

Each category maintains its own registry, which can be selectively modified or cleared as needed.

---

## API Usage

- `export_asynchronous *names` — Mark specified tasks as asynchronously exported.
- `export_synchronous *names` — Mark specified tasks as synchronously exported.
- `export_exec *names` — Designate tasks as exported for execution.
- `export_stream *names` — Designate tasks as exported with output streaming.
- `unexport *names` — Remove tasks from all export lists.
- `clear_exports` — Remove all exported tasks in all modes.
- `all_exports`/`task_exports` — Get the complete list of all currently exported tasks (in any category).

All of these methods support both symbols and strings for task names.

### Example Idioms

To declare a task as suitable for remote execution (i.e., export it for asynchronous/external runners):

```ruby
export_asynchronous :long_running_task, :annotation_exported_process
```

To restrict a task so it is only accessible for direct execution:

```ruby
export_exec :immediate_action
```

To fully clear the export state (all tasks become internal):

```ruby
clear_exports
```

### Removing Exports

If you need to dynamically remove tasks from any exported state (e.g., for deprecation, access control, or reconfiguration), use:

```ruby
unexport :task_name1, :task_name2
```

Tasks are removed with both their string and symbol representation, ensuring robust lookup.

---

## Integration and Effects

Tasks that are not exported will not be runnable or visible via the CLI or external HTTP/queue endpoints. This mechanism is central to the modular, secure, and controlled nature of workflow APIs in Scout.

Combined with the rest of the `Workflow` module infrastructure, task exporting supports both flexible development (with private helper tasks and prototype APIs) and robust production deployment where only trusted, documented endpoints are made available.

---

## Example from the Command-Line Interface

Export lists directly affect what appears in CLI commands such as:

- `scout workflow <workflow> <command>`
- `scout workflow task <workflow> <task>`

Attempting to invoke a non-exported task or step from the CLI will result in clear errors or hidden commands, depending on the export state.

---

**Note:** See the main [Workflow documentation](#workflow) and the test suite for further real-world examples of export declarations and their effects on workflow composition, CLI presentation, and API structure.