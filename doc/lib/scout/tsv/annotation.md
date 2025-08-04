# Annotation Subsystem and API

The annotation framework within TSV provides a powerful mechanism for associating rich, structured metadata with strings, arrays, and domain-specific objects. Annotations allow data to carry additional fields, types, and JSON-encoded information, track their provenance, and support advanced introspection and roundtrips between data and tabular representation.

## Overview

- **Annotation API (`Annotation` module):** Enables attaching arbitrary fields and metadata (“annotations”) to any Ruby object (commonly strings or arrays), using a transparent wrapper.
- **Annotation Hash:** Each annotated object carries an `annotation_hash`, which records field names and values, supports dynamic (per-class, per-object) fields, and enables type-safe, layered metadata.
- **Keys and Identity:** Annotated values receive unique keys (via `annotation_id`) and can be grouped and round-tripped as TSV records.

### Integration with TSV

- When serializing, annotated objects (including arrays such as `AnnotatedArray`) automatically preserve their annotations in TSV columns.
- Round-tripping (object → TSV → object) will reliably preserve all annotated fields, values, and types.

## Key Methods and Behaviors

### Defining Annotations

You can define custom annotation fields for a class/module:

```ruby
module AnnotationClass
  extend Annotation
  annotation :code, :code2
end
```

This declares that instances may be annotated with `:code` and `:code2`.

### Annotating Objects

To annotate objects:

```ruby
str = "string1"
AnnotationClass.setup(str, :c11, :c12)
```

The string will now respond to `.code` and `.code2`, and carry metadata.

### TSV Serialization of Annotations

Convert annotated objects to TSV records:

```ruby
str1, str2 = "string1", "string2"
AnnotationClass.setup(str1, :c11, :c12)
AnnotationClass.setup(str2, :c21, :c22)
tsv = Annotation.tsv([str1, str2], :all)
assert_equal str1, tsv[str1.annotation_id + "#0"]["literal"]
assert_equal :c11, tsv[str1.annotation_id + "#0"]["code"]
```

You can include JSON metadata columns:

```ruby
assert_equal "c11", JSON.parse(Annotation.tsv([str1, str2], :code, :JSON)
  .tap { |t| t.unnamed = false }[str1.annotation_id + "#0"]["JSON"])["code"]
```

### Loading Annotated Objects from TSV

You can deserialize annotated objects from TSV hashes:

```ruby
tsv = Annotation.tsv([str1, str2], :all)
list = Annotation.load_tsv(tsv)
assert_equal [str1, str2], list
assert_equal :c11, list.first.code
```

Arrays with annotations can also be handled and will result in annotated arrays:

```ruby
a = [str1, str2]
code = "Annotation String 2"
AnnotationClass.setup(a, code)
a.extend AnnotatedArray
assert_equal code, Annotation.load_tsv(Annotation.tsv(a, :all)).code
```

### Annotation Fields and Data Model

- **Standard Fields:** By default, fields such as `literal`, `annotation_types`, and `JSON` can be automatically generated/extracted.
- **Custom Fields:** Any annotation registered can be included as a TSV column.

Values are properly encoded (including conversion of arrays to pipe-separated strings, with prefixes such as `"Array:"`) and decoded for roundtrip fidelity.

## Persistent Annotation Repositories

Using the `Persist.annotation_repo_persist` method, complex annotation objects (including arrays and annotated arrays) can be written to, and retrieved from, persistent files backed by TokyoCabinet. These repositories support:

- **Roundtrip semantics:** Retrieval will yield annotated objects with correct code fields and annotation structure, even across process boundaries.
- **Single, Empty, and Nil Handling:** Efficiently encodes and decodes cases of `nil` or empty arrays.
- **Array and AnnotatedArray Handling:** Both regular and annotated arrays are persisted with type awareness.

Example (from tests):

```ruby
annotation = Persist.annotation_repo_persist(repo, "My annotation simple") do
  AnnotationClass.setup("TESTANNOTATION", code: "test_code")
end
assert_equal "TESTANNOTATION", annotation
assert_equal "test_code", annotation.code
```

Arrays of annotated objects:

```ruby
annotation = Persist.annotation_repo_persist(repo, "My annotation") do
  [
    AnnotationClass.setup("TESTANNOTATION", code: "test_code"),
    AnnotationClass.setup("TESTANNOTATION2", code: "test_code2")
  ]
end.first
assert_equal "TESTANNOTATION", annotation
assert_equal "test_code", annotation.code
```

AnnotatedArray objects (arrays carrying annotation at the array level):

```ruby
a = AnnotationClass.setup(["TESTANNOTATION", "TESTANNOTATION2"], code: "test_code")
a.extend AnnotatedArray
annotation = Persist.annotation_repo_persist(repo, "My annotation array") { a }.first
assert_equal "TESTANNOTATION", annotation
assert_equal "test_code", annotation.code
```

### Robustness and Edge Cases

- **Nil and Empty Values:** Special markers (`NIL`, `EMPTY`) ensure that loading will return `nil` or `[]` as appropriate.
- **Exception Safety:** Once a value is persisted, subsequent attempts to retrieve it (even if the block raises) will return the previously stored value, avoiding accidental loss.
- **Customizable Fields:** By changing the setup of the repository TSV table, you can persist custom combinations of fields.
- **Interoperability:** Works seamlessly with all core TSV facilities, and can translate between memory and persistent file-based annotation storage.

## Summary

The annotation system enables fine-grained, structured metadata attachment and round-trip preservation for any Ruby object, with first-class TSV integration (serialization and deserialization), value casting, custom field definition, and bulk persistent storage using fast TokyoCabinet backends. The test suite demonstrates and covers complex cases: singletons, arrays, nil/empty handling, AnnotatedArray structures, and multi-field annotation.

**See also:**  
- `Annotation.tsv`  
- `Annotation.load_tsv`  
- `Persist.annotation_repo_persist`  
- Tests in `test/scout/tsv/annotation/test_repo.rb` and `test/scout/tsv/test_annotation.rb` for comprehensive behaviors.

---