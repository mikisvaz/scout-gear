# Entity: Object Utilities

The `Entity::Object` module provides foundational utility methods for enhanced introspection and management of entities within the `Entity` framework. Included automatically in all modules that extend `Entity`, these utilities underpin property aggregation, caching, and inheritance inspection—capabilities that are essential when building complex or deeply-composed entity types.

## Core Methods

### `entity_classes`

Returns a list of all annotation types for the object that are entities—that is, modules in the annotation ancestry that extend `Entity`. This method enables enumerating all layers of entity behavior present in a value:

```ruby
def entity_classes
  annotation_types.select{|t| Entity === t}
end
```

This method supports downstream features such as property aggregation and entity hierarchy introspection.

### `base_entity`

Identifies the most fundamental entity (typically the original module to extend `Entity`) in the entity ancestry chain. It is defined as the last entity-class in the annotation ancestry:

```ruby
def base_entity
  entity_classes.last
end
```

This is used for resolving inheritance bases and low-level type inspection.

### `_ary_property_cache`

Returns a per-object memoized cache for properties, used to efficiently store and retrieve evaluated property values:

```ruby
def _ary_property_cache
  @_ary_property_cache ||= {}
end
```

This cache is leveraged by property accessors and caching layers in `Entity::Property`, ensuring that expensive property computations are optimized over the object's lifetime.

### `all_properties`

Returns a full, flattened list of all property definitions supplied by every entity module present in the object's ancestry. This enables both enumeration and inheritance-aware property resolution:

```ruby
def all_properties
  entity_classes.inject([]){|acc,e| acc.concat(e.properties) }
end
```

This is critical for features like persistent property export, dynamic introspection, and meta-programming around available entity attributes.

## Practical Context

Although the `Entity::Object` module is not directly tested in the suite, its methods power core features such as all-properties aggregation and entity-type reflection, which are actively exercised and validated in integrated entity module tests (for example, in property behaviors and ancestry walking with custom entity hierarchies).

Its role is particularly apparent in complex or composed entities where multiple property layers and extensions may be in effect: these utilities ensure reliable, accurate discovery and utilization of all relevant entity facets.