## Documentation

The `Workflow` module provides facilities for embedding and parsing rich documentation directly into each workflow and its tasks. Documentation is designed to be accessible both programmatically and via command-line interfaces, enabling introspection, usage display, and automated help generation.

### Markdown-based Documentation

Workflows may include Markdown files (`workflow.md` or `README.md`) alongside their code. The method `documentation_markdown` reads the appropriate Markdown file from the workflow's library directory, if present, serving as the primary documentation source.

This documentation is parsed using several class-level helpers:

- `doc_parse_first_line(str)`: Extracts the first line as a title, with the remainder as the detailed doc.
- `doc_parse_up_to(str, pattern, keep)`: Captures documentation up to a matching pattern, optionally retaining or dropping the matched line.
- `doc_parse_chunks(str, pattern)`: Splits documentation into task-marked chunks based on headings (e.g., `## task_name`).

`parse_workflow_doc(doc)` then assembles the workflow's structure into:

- `:title` – the main summary line (first line or code title)
- `:description` – the description block
- `:task_description` – any section before enumerated tasks
- `:tasks` – a dictionary mapping task names (or `workflow#task` signatures) to their documentation text

### Integration with Workflow Code

When the documentation is accessed via the `documentation` accessor, it is parsed—ensuring that:
- If explicit Ruby code fields `@description` or `@title` are present (via `self.description` or `self.title`), they take precedence if Markdown documentation is missing these fields.
- Task documentation (from the parsed Markdown) is pushed directly into each `Task`'s `description` attribute, as long as the workflow and task exist and match.

This means the documentation is always consistent between the Markdown files and the in-memory task structures, enhancing self-help and command-line usability. If documentation references tasks that don't exist in the current workflow, a log message is printed for diagnostic purposes.

### Usage Example (from the Test Suite)

Workflow definition with explicit title and description:
```ruby
module UsageWorkflow
  extend Workflow

  self.title = "Workflow to test documentation"
  self.description = "Use this workflow to test if the documentation is correctly presented"

  desc "Desc"
  input :array, :array, "Array"
  task :step1 => :string do; end

  dep :step1
  desc "Desc2"
  input :float, :float, "Float"
  task :step2 => :string do; end
end
```

Test cases demonstrate documentation access:
```ruby
def test_usage
  assert_match 'test', UsageWorkflow.documentation[:title]
  assert_match 'presented', UsageWorkflow.documentation[:description]
end
```

And Markdown parsing:
```ruby
doc =<<-EOF
summary

description

# Tasks

## task1

task 1 summary

task 1 description

## task2
task 2 summary

task 2 description
EOF

assert_includes Workflow.parse_workflow_doc(doc)[:tasks], 'task1'
assert_includes Workflow.parse_workflow_doc(doc)[:tasks]['task2'], 'task 2 description'
```

### Edge Cases and Robustness

- Supports both inline Ruby descriptions and external Markdown documentation interchangeably.
- Integrates parsed markdown into both workflow and task records.
- Ignores documentation for tasks that do not exist in the workflow (with a warning message).
- Documentation is robust even if some sections (title/description) are missed in markdown; the workflow-level values are used as fallbacks.

### Summary

Scout's `Workflow` documentation system blends code, markdown, and CLI usage output, creating a discoverable, always-up-to-date help interface. This provides robust self-documentation for users and developers, equally accessible from Ruby or the command line.

For more examples, see the `test/scout/workflow/test_documentation.rb` test file.