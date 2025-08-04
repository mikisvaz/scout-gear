# Entity Property

The `Entity::Property` module is central to adding rich, customizable, and persistent property methods to Entity-extended modules. It empowers developers to define properties with diverse execution contexts (single object, array, multi-object) and robust persistence, with full support for caching, annotation, and batch processing semantics. This infrastructure is designed for both straightforward attributes and complex computed properties.

## File Overview

The `Entity::Property` module provides APIs for declaring properties, setting their types, enabling/disabling persistence, and handling the property value resolution for both single items and collections. Key features include automatic method injection, intelligent method dispatch based on context, comprehensive property persistence infrastructure, and built-in annotation integration.

## Usage & Declaration

**Extending with Properties**  
Start by extending your module with `Entity`, then declare properties with the `.property` method. The property type determines how and when the property executes for arrays vs. single items:

From the test suite:

```ruby
module ReversableString
  extend Entity

  self.annotation :foo, :bar

  property :reverse_text_ary => :array do
    $count += 1
    self.collect{|s| s.reverse}
  end

  property :reverse_text_single => :single do
    $count += 1
    self.reverse
  end

  property :multiple_annotation_list => :multiple do 
    $processed_multiple.concat self
    res = {}
    self.collect do |e|
      e.chars.to_a.collect{|c| ReversableString.setup(c) }
    end
  end
end
```

## Property Types

Property types define the shape and scope of computation:

- `:single` — Runs on a single item (scalar context).
- `:array` — Runs on the array as a whole.
- `:both` — Adapts to both (with transparent dispatch).
- `:multiple` — Designed for batch aggregation, annotation, and results per array member.

### Examples from tests

#### Single Properties

Single properties run on an individual instance:

```ruby
a = "String1"
ReversableString.setup(a)

assert_equal "1gnirtS", a.reverse_text_single
```

#### Array Properties

Array properties receive the full array and typically map or aggregate:

```ruby
a = ["String1", "String2"]
ReversableString.setup(a)
assert_equal "2gnirtS", a.reverse_text_ary.last
```

#### Both-type Properties

These work for both single values and arrays, adapting as needed:

```ruby
a = "String1"
assert_equal "1gnirtS", a.reverse_both

a = ["String1"]
assert_equal "1gnirtS", a.reverse_both.last
```

#### Multiple Properties

Multiple properties perform batch operations, handling annotation as needed:

```ruby
array = ReversableString.setup([string1, string2])
assert_equal [string1, string2].collect{|s| s.chars}, array.multiple_annotation_list
assert_equal string1.length, array[0].multiple_annotation_list.length
```

## Property Persistence

Properties can be persisted (results cached and stored for repeatability and efficiency). You can persist a property, unpersist it, and check its persistence status:

```ruby
ReversableString.persist :reverse_text_ary_p, :marshal
assert ReversableString.persisted?(:reverse_text_ary_p)

ReversableString.unpersist :reverse_text_ary_p
refute ReversableString.persisted?(:reverse_text_ary_p)
```

Persisted computations are reused, reducing recomputation. Random properties illustrate this:

```ruby
r1 = a.random
r2 = a.random
assert_not_equal r1, r2

ReversableString.persist :random
r1 = a.random
r2 = a.random
assert_equal r1, r2
```

## Annotation-Aware Properties

Some properties return or operate on annotation-aware arrays. For example:

```ruby
string = 'aaabbbccc'
ReversableString.setup(string)
assert_equal string.length, string.annotation_list.length
assert_equal [], string.annotation_list_empty
```

Handling of multiple annotations is robust and tracks unique processing:

```ruby
array = ReversableString.setup([string2, string3, string4])
assert_equal string2.length, array.multiple_annotation_list[0].length
```

## Caching and Efficiency

Entity property calls are cached at the array level. This significantly reduces computation:

```ruby
$count = 0
a.reverse_text_ary.last # $count is incremented to 1
a.reverse_text_ary.last # cache prevents further increment
```

The cache is per array, and is cleared with methods such as `_ary_property_cache.clear`.

## Purging Entity Enhancements

Entity-enhanced objects can be reverted ("purged"), removing all added property methods, making the result a plain object:

```ruby
string = "test_string"
ReversableString.setup string
assert string.respond_to?(:reverse_text_single)
assert ! string.purge.respond_to?(:reverse_text_single)
```

## Introspection

The set of properties is always accessible both from the entity module and its instances:

```ruby
assert ReversableString.setup("TEST").all_properties.include?(:reverse_text_ary)
assert_equal ReversableString.setup("TEST").all_properties, ReversableString.properties
```

## Edge Cases & Robustness

- **Context Discrimination**: Properties automatically dispatch based on whether self is a single or array context.
- **Multiple Properties**: Properly annotate missing items and aggregate results.
- **Argument Passing**: Property blocks support argument and keyword argument passing (`.times(times)` style).
- **Cache Coherence**: Cache is safely keyed on arguments.
- **Method Removal**: `purge` cleanly removes dynamic methods.
- **No Side Effects**: All side effects (like $count or $processed_multiple) are test-visible.

## Conclusion

`Entity::Property` transforms modules into flexible, annotation-friendly, and persistable value-object classes. Its thorough test suite demonstrates resilience in single and group execution, persistent caching, efficient batch and annotation handling, and strict method enhancement reversal—making it a comprehensive foundation for entity-like properties in Ruby.