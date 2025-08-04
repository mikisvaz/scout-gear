# KnowledgeBase - Enrichment

The enrichment functionality within the `KnowledgeBase` class provides statistical analysis of sets of entities in relation to a registered association or database. This is especially relevant in bioinformatics and data science workflows, where users seek to determine which relationships or attributes are statistically significantly overrepresented within a selected group of entities.

## Method Overview

The core enrichment method is:

```ruby
def enrichment(name, entities, options = {})
  require 'rbbt/statistics/hypergeometric'
  database = get_database(name, options)
  entities = identify_source name, entities
  database.enrichment entities, database.fields.first, :persist => false
end
```

This method performs a hypergeometric enrichment analysis, leveraging the `rbbt/statistics/hypergeometric` module to determine statistical significance of associations between a provided set of `entities` and the entries of the specified database.

### How It Works

- **Database Selection:** Using `get_database(name, options)`, the relevant association database is retrieved from the knowledge base's registry, allowing for user-supplied options (e.g., restricting to a subset, filtering, etc.).
- **Entity Identification:** `identify_source` ensures that the provided `entities` are translated into their canonical or database-appropriate identifiers, handling aliases, alternate IDs, and the knowledge base's internal mapping logic.
- **Statistical Test:** The enrichment test is performed by invoking `database.enrichment`, which uses the hypergeometric distribution to quantify how likely it is to observe the overlap between `entities` and the database field under a random background assumption. The field specified is typically the first field in the database, and persistence is set to false to ensure a fresh calculation.

## Usage and Customization

The enrichment analysis is commonly used to identify overrepresented targets, terms, or related entities within a selected group. This is generic across all knowledge bases and data domains supported.

Parameters to `enrichment`:
- `name`: The symbol or string name of a registered database or association.
- `entities`: The array or collection of source entities to analyze.
- `options`: Optional hash of further parameters to select the database or modify its behavior.

The results, returned from `database.enrichment`, typically include p-values, counts, and details on which terms or targets are most strongly enriched in the input set.

## Example Workflow

While the provided test suite does not include an explicit worked example for direct enrichment usage, the mechanism is tightly integrated with typical entity and association registration and querying functions described throughout the KnowledgeBase documentation.

For instance, after registering a database and selecting a subset of entities (e.g., all people with a given property or in a family), you can analyze overrepresentation for another association by calling the enrichment method with the relevant subset. The canonical process is:

1. Register or select the association/database to be tested.
2. Prepare or select a group of entities of interest.
3. Invoke `knowledge_base.enrichment(association_name, entities)` and examine the results.

## Edge Cases and Behaviors

- The method automatically handles entity translation, so users can supply either identifiers or known entity names.
- If the database is not found or is missing essential fields, an error is raised as per the database or registry logic.
- The statistical calculation is not persisted unless otherwise specified, ensuring fresh analyses each time.

## Summary

The enrichment subsystem of `KnowledgeBase` provides statistically robust insights into the structure and connectivity of entities within the knowledge graph. By supporting streamlined integration of entity selection, database resolution, and statistical testing, it empowers advanced exploration, validation, and hypothesis generation in structured datasets.