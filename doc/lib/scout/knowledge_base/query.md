## Query

The query subsystem of the `KnowledgeBase` class offers flexible, attribute-aware methods for extracting and traversing relationships between entities, making it ideally suited for knowledge graph traversal, subgraph selection, and exploration of association networks. Methods such as `subset`, `children`, `parents`, `all`, and `neighbours` provide both breadth and semantic precision for a wide range of querying needs.

### Core Query Methods and Their Usage

#### `subset`

The `.subset` method forms the core of the querying API, allowing extraction of relationship matches from an association by specifying the name and constraints on source and/or target entities. This method flexibly accepts different constraint shapes: symbol `:all`, attribute hashes, or annotated arrays, as described in the entity module.

Test examples illustrate direct usage:

```ruby
matches = kb.subset(:parents, :all)
assert_include matches, "Clei~Domingo"

matches = kb.subset(:parents, target: :all, source: ["Miki"])
assert_include matches, "Miki~Juan"
```

This approach enables selecting all parent relationships or restricting to those sourced from a specific individual such as "Miki".

#### `children` and `parents`

Semantic access to upstream and downstream relationships is available via `.children` and `.parents`. These methods automatically resolve identifiers and instantiate entities with correct options and type.

Worked example:

```ruby
assert_include kb.children(:parents, "Miki").target, "Juan"
assert_include kb.children(:brothers, "Miki").target, "Isa"

parents = matches.target_entity

assert_include parents, "Juan"
assert Person === parents.first
assert_equal "en", parents.first.language
```

- `children(:parents, "Miki")` finds the children of "Miki" in the "parents" association.
- Returned entity objects inherit metadata such as language, as configured via entity options.

#### Attribute-Aware Entity Resolution

Automatically, query matches are enriched with entity attributes as defined in the knowledge base's configuration. For instance:

```ruby
assert_equal "en", parents.first.language

matches = kb.subset(:brothers, target: :all, source: ["Miki"])
assert_equal "es", matches.first.source_entity.language
```

Here, the results are not merely identifiers; their attributes (e.g., language) are preserved and accessible, enabling downstream, option-sensitive enrichment.

#### `all`

The `.all` method quickly lists all keys (usually source entries) for a registered relationship:

```ruby
assert_include kb.all_databases, :brothers
```

#### Handling Directionality

The knowledge base respects directionality and supports undirected associations. As seen with `:brothers`, registered with `undirected: true`, methods like `.neighbours` present results accordingly.

### Edge Case Handling

- Attempts to query with nil, empty, or mismatched source/target constraints return empty result sets, protecting the user from invalid lookups.
- Block support in `.subset` enables custom filtering on any result set.
- Both keyed and positional query idioms (e.g., `subset(:name, hash)`, `subset(:name, :all)`) are accepted.

### Summary

The KnowledgeBase query subsystem provides advanced, composable, and attribute-preserving methods for querying entity relationships. Its design and robust test suite guarantee correct handling of types, metadata, directedness, and input idioms, as demonstrated in the worked examples above. This allows for direct, expressive, and metadata-rich extraction of knowledge associations in practical systems.