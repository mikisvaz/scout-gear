## TSV Path Integration

The `tsv/path` subsystem seamlessly connects the `Path` abstraction to TSV operations, allowing TSV files to be manipulated directly through `Path` instances. This elevates file I/O workflows with an idiomatic, chainable API, central to efficient and readable data engineering, scientific, and bioinformatics pipelines in `Scout`.

### Functional Overview

By extending the `Path` object, this subsystem enables direct method calls such as `tsv`, `tsv_options`, and `index` on files, making TSV access and metadata discovery straightforward and expressive. Additionally, automatic identifier file resolution is supported for datasets requiring enrichment or mapping.

### Example Usage: TSV File Opening and Persistence via Path

From the test suite:

```ruby
content =<<-EOF
#Id    ValueA    ValueB    OtherID
row1    a|aa|aaa    b    Id1|Id2
row2    A    B    Id3
row2    a    a    id3
EOF

tsv = nil
TmpFile.with_file(content) do |filename|
  Path.setup(filename)
  tsv = filename.tsv persist: true, merge: true, type: :list, sep: /\s+/
  assert_equal %w(ValueA ValueB OtherID), tsv.fields
  tsv = filename.tsv persist: true, merge: true, type: :list, sep: /\s+/
  assert_equal %w(ValueA ValueB OtherID), tsv.fields
end
```

This demonstrates:

- **Direct File Invocation:** The `.tsv` method opens the file referenced by the `Path` object `filename`, parsing it per specified options (including `persist: true`, `merge: true`, `type: :list`, and custom separator).
- **Persistence:** Subsequent accesses with identical options use the same on-disk table, supporting scalable, repeatable data workflows.
- **Header Extraction:** The returned object has fields (`ValueA ValueB OtherID`) derived directly from file headers.

### Additional Path Methods

- **`tsv_options(options = {})`:** Parses and returns the TSV’s parsing and annotation options, either from headers or arguments, offering programmatic introspection.
- **`index(*args, **kwargs, &block)`:** Exposes `TSV.index`, enabling advanced single-field, range, or point indexing directly on the file object.
- **`identifier_file_path`:** Automatically discovers and returns a sibling identifier file for the dataset, if present—enabling identifier mapping without manual path management.

### Integration Practices

- Always prepare files with `Path.setup(filename)` for full enhancement.
- Prefer the `.tsv` method on `Path` objects over lower-level open/parsing calls for clear, robust, and option-rich TSV access in your pipelines.
- Use related methods (`tsv_options`, `index`, and `identifier_file_path`) for introspection, indexing, and automagic identifier linkage.

### Summary

The Path-TSV bridge ensures that TSV resource access is both concise and powerful, fully leveraging the `Scout` ecosystem’s capabilities for file handling, metadata management, and efficient tabular computation. This facilitates rapid prototype-to-production workflows in research and analytics environments.