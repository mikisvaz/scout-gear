## Traverse

The `traverse` capability in the `KnowledgeBase` class enables expressive, rule-based traversal of the entity relationship graph, supporting wildcards, variable assignments, attribute filtering, multi-step queries, and inter-database joins. Traversal is encapsulated by the `KnowledgeBase::Traverser` class and is made available via `KnowledgeBase#traverse`.

### Overview of Traversal Rules

Each traversal consists of a sequence of rules, typically in the format:

```
source_entity association target_entity [ - conditions ]
```

- `source_entity` and `target_entity` can be explicit entity names, identifiers, list references (prefixed with `:`), or wildcards (e.g., `?var`).
- `association` is the name of a registered relationship (database/edge) such as `brothers`, `parents`, or custom links.
- Optional `[ - conditions ]` applies attribute-based filtering to restrict matches.
- Assignments (via `=`) and accumulator blocks (delimited by `{}`) further extend expressiveness for collecting or constraining variable values.

### Worked Examples from Test Suite

#### Single-step Traversal with Wildcards

Find all brothers for "Miki" and assign results to wildcard `?1`:

```ruby
rules = []
rules << "Miki brothers ?1"
res =  kb.traverse rules
assert_include res.first["?1"], "Isa"
```

#### Extracting Information about Relationships

Obtain all parent relationships and inspect their additional data (e.g., relationship type):

```ruby
rules = []
rules << "Miki parents ?1"
entities, paths = kb.traverse rules
assert_include paths.first.first.info, "Type of parent"
```

#### Reverse Traversal with Wildcards

Query for all entities that have "Domingo" as a parent:

```ruby
rules = []
rules << "?1 parents Domingo"
entities, paths = kb.traverse rules
assert_include entities["?1"], "Clei"
```

#### Multi-step Graph Traversal

Chain rules to walk a path through multiple types of associations, binding results to subsequent variables:

```ruby
rules = []
rules << "Miki marriages ?1"
rules << "?1 brothers ?2"
res =  kb.traverse rules
assert_include res.first["?2"], "Guille"
```

#### Attribute Filtering

Restrict matches to links with a certain property (for example, only fathers):

```ruby
rules = []
rules << "Miki parents ?1 - 'Type of parent=father'"
entities, paths = kb.traverse rules
assert_equal entities["?1"], ["Juan"]
```

#### Assignments and Transitive Queries

Variables can be assigned on-the-fly to select intermediary results, then reused in subsequent rules:

```ruby
rules = []
rules << "?target =brothers 001"
rules << "?1 brothers ?target"
res = kb.traverse rules
assert_include res.first["?1"], "Isa"
assert_include res.first["?target"], "Miki"
```

#### Multi-entity and Identifier Handling

Traversal will resolve entity names and identifiers via knowledge base mapping logic, ensuring flexible support for alternate labels or codes:

```ruby
rules = []
rules << "001 brothers ?1"
res = kb.traverse rules
assert_include res.first["?1"], "Isa"
```

#### Multiple Rule Assignment and Variable Intersection

Complex traversals can collect matches that satisfy constraints across multiple rules:

```ruby
rules_str=<<-EOF
?target1 =gene_ages SMAD7
?target2 =gene_ages SMAD4
?target1 gene_ages ?age
?target2 gene_ages ?age
?1 gene_ages ?age
EOF
rules = rules_str.split "\n"
res = kb.traverse rules
assert_include res.first["?1"], "MET"
```

Or using accumulator blocks:

```ruby
rules_str=<<-EOF
?target1 =gene_ages SMAD7
?target2 =gene_ages SMAD4
?age{
  ?target1 gene_ages ?age
  ?target2 gene_ages ?age
}
?1 gene_ages ?age
EOF
rules = rules_str.split "\n"
res = kb.traverse rules
assert_include res.first["?1"], "MET"
```

#### Inter-database Wildcarding

Wildcard database names allow rules to flexibly traverse any registered association:

```ruby
rules = []
rules << "SMAD4 ?db ?1"
res = kb.traverse rules
```

### API and Return Values

The `#traverse` method returns an array `[assignments, paths]`:
- `assignments` is a hash mapping wildcards (`?var`) to lists of matched entities.
- `paths` (when requested) is a collection of the actual traversed paths between entities, each as a sequence of matched edge instances/records.

### Usage Patterns and Behaviors

- Wildcards (`?var`) propagate values through the traversal, supporting multi-step graph walks and variable rebinding.
- Assignments (`?var =association value`) let you pre-bind variables for use in later steps.
- Attribute filtering via `- 'key=value'` enables semantic subsetting (e.g., only "father"-type relationships).
- Both directed and undirected relationships are supported transparently, respecting configuration at registration time.
- If no namespace is present, traversal operates over global context; otherwise, it maintains isolated context.

### Edge Case Handling and Robustness

- If a variable is not matched in the path logic, or if no eligible paths exist, results are empty but no error is raised.
- Variable rebinding during assignments/accumulator blocks is isolated and state is managed cleanly across rules.
- List references (using `:listname`) are automatically loaded and expanded.

### References

For real-world traversal workflows and more coverage, see `test/scout/knowledge_base/test_traverse.rb`.

---

This subtopic demonstrates the advanced, expressive querying and graph-walk capabilities of the `KnowledgeBase#traverse` method, providing a query language-like interface for extracting complex, condition-dependent insights from your knowledge base.