# Format

Entity’s format mechanism enables dynamic and robust assignment, registration, discovery, and lookup of entity formats, making it central to how entities identify, compare, and convert among naming conventions, types, or representation schemes.

## Format Assignment

When an entity module or class is extended, its default format can be assigned through the `.format=` method. This supports both single and multiple format names, allowing an entity to be referenced by any of its aliases:

```ruby
base.format = base.to_s
```

If multiple names are set, each can serve as a lookup route to the entity type.

## Format Registry and Indexing

Formats are tracked via the global `Entity.formats` registry, an instance of `Entity::FormatIndex`. This registry provides flexible storage and fast lookup for format associations. You may register a format directly:

```ruby
index = Entity::FormatIndex.new
index["Ensembl Gene ID"] = "Gene"
Entity::FORMATS["Ensembl Gene ID"] = "Gene"
```

## Format Matching and Lookup

`Entity::FormatIndex` ensures that format keys can be looked up with exact names or parenthesized/infix variants. This enables matching against strings like `"Transcription Factor (Ensembl Gene ID)"` or `"Ensembl Gene ID"` equally.

From the test suite:

```ruby
assert_equal "Gene", index["Ensembl Gene ID"]
assert_equal "Gene", index["Transcription Factor (Ensembl Gene ID)"]

assert_equal "Ensembl Gene ID", Entity::FORMATS.find("Ensembl Gene ID")
assert_equal "Ensembl Gene ID", Entity::FORMATS.find("Transcription Factor (Ensembl Gene ID)")

assert_equal "Gene", Entity::FORMATS["Ensembl Gene ID"]
assert_equal "Gene", Entity::FORMATS["Transcription Factor (Ensembl Gene ID)"]
```

**Key behaviors:**
- `find`: Returns the registered key for an exact or embedded match.
- `[]`: Fetches the format value for an exact or embedded match.
- Assignment (`[]=`): Automatically invalidates internal caches to preserve lookup correctness.

## Format-aware Entity Preparation

When creating or wrapping instances, `Entity.prepare_entity` leverages format information to ensure values (strings, arrays, numerics) are properly converted, duplicated, or extended as entities, matching the canonical or declared format. Annotation extension occurs when appropriate for arrays, ensuring entity information is retained throughout value transformations.

## Edge Cases and Consistency

- Format lookup is case-consistent and works regardless of whether the query is a "bare" format or nested (e.g., parenthesized variant).
- Internal caches in the registry guarantee fast repeat lookups and are cleared when assignments occur to maintain consistency across changes.
- Empty or minimal entities still register and respond to format queries, supporting flexible composition.

## Summary

Entity's format system—anchored by `Entity.formats` and `Entity::FormatIndex`—delivers flexible, high-performance format assignment, lookup, and matching. Entities can register under multiple names, look up formats by variant and infix, and always resolve to the canonical value type. This underpins robust and adaptable naming, conversion, and cross-referencing in all entity-based domain modeling.