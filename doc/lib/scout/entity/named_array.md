## NamedArray

The `Entity::NamedArray` module enriches array-like objects with named-key access, supporting retrieval and implicit entity conversion by semantic name. This facility is key when dealing with arrays that act as records, where each value is associated with a particular field or entity type and may require property-rich behavior.

### Named Key and Field-Based Access

With `Entity::NamedArray`, accessing an element by string or symbol name transparently locates the value at the corresponding field position, then passes it through `Entity.prepare_entity` using the field as context. This means the returned object not only represents the raw value, but is also "upgraded" into its appropriate entity type, inheriting entity properties and behaviors.

If the field name or position is not found, `nil` is returned. Integer keys are also supported; if the integer corresponds to an index in the fields array, the entity preparation uses the field name at that position.

#### Example from Test Suite

```ruby
a = NamedArray.setup(["a", "b"], %w(SomeEntity Other))
assert a["SomeEntity"].respond_to?(:prop)
```

- Here, a `NamedArray` is created with two entries: `"a"` and `"b"`, tagged as `"SomeEntity"` and `"Other"`.
- When accessing `a["SomeEntity"]`, the method locates the corresponding value ("a"), and automatically prepares it as a "SomeEntity" entity. If a property called `prop` is defined for "SomeEntity", this is now available: `a["SomeEntity"].respond_to?(:prop)` is true.
- If an unrecognized key is used, the result is `nil`.

### Entity System Integration

Returns from key-based access are elevated to entity objects where possible. This enables seamless use of entity-defined methods and properties, making entity-rich logic possible regardless of whether the source was a primitive array, as illustrated in the test above.

### Edge Case Handling

- Unrecognized names yield `nil`.
- Integer keys are resolved using the `@fields` array if present; otherwise, normal array indexing occurs.
- All returned elements are entityified if possible via the central `Entity.prepare_entity`, guaranteeing consistent type and property support.

### Summary

Use `Entity::NamedArray` when you require array-like collections that can be queried by field or entity name, yielding entity-typed objects with all their declared properties and behaviors. This extension is especially effective for datasets, records, or multi-attribute entities managed as arrays but accessed as if by named fields within the Entity framework.