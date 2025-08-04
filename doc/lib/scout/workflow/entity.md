## Entity: Extended Workflow Support for Domain Entities

The `EntityWorkflow` module provides an advanced extension point for workflows that manipulate domain-specific entities or collections thereof. It enables object-oriented, property-driven workflows where "entities" (such as biological samples, users, files, etc.) are the unit of organization and computation.

### Core Features

- **Entity Name & Helper Registration:**  
  By setting the `entity_name`, the module defines a primary accessor for the underlying entity, and automatically provides a `helper` with this name.

- **Integration with Workflow and Entity:**  
  When a module `extend EntityWorkflow`, it also extends both `Workflow` and `Entity`, gaining all features from both.

- **Property-Style Task Definition:**  
  Tasks can be defined so that they look and behave like entity "properties". This enables both single-entity and list/projected computations.

- **Annotation-Driven Input & Metadata:**  
  Supports per-entity annotations, custom inputs, and property configuration via helper methods (e.g., `annotation_input`).

- **Flexible Task Type Facets:**  
  Task variants for single entities, lists, and more are provided, with corresponding helpers for property, entity, and list jobs.

### Usage Patterns from Test Cases

#### Defining an Entity Workflow

The test suite demonstrates how to use `EntityWorkflow` to define property and entity/list jobs. Below is the idiomatic pattern for such usage, as found in the test file:

```ruby
@ewf = Module.new do
  extend EntityWorkflow

  self.name = 'TestEWF'

  property :introduction do
    "Mi name is #{self}"
  end

  entity_task hi: :string do
    "Hi. #{entity.introduction}"
  end

  list_task group_hi: :string do
    "Here is the group: " + entity_list.hi * "; "
  end

  list_task bye: :array do
    entity_list.collect do |e|
      "Bye from #{e}"
    end
  end
end
```

#### Using Entity and Property Tasks

Creating an entity instance and invoking property-style methods or tasks:

```ruby
ewf = get_EWF

e = ewf.setup("Miki")

assert_equal "Mi name is Miki", e.introduction
assert_equal "Hi. Mi name is Miki", e.hi
```

For entity _lists_:

```ruby
l = ewf.setup(["Miki", "Clei"])

assert_equal 2, l.hi.length
assert_include l.group_hi, "group: "
assert_equal 2, l.bye.length
```
- `e.hi` returns a single greeting for one entity.
- `l.hi` returns an array of greetings (one per entity).
- `l.group_hi` gives a group-level message by aggregating entity results.
- `l.bye` projects a "bye" property across all entities.

#### Annotation Inputs

`EntityWorkflow` allows entity properties to be annotated and referenced as input types. This is managed via the `annotation_input` class method which registers additional metadata for entity-driving tasks.

#### Integration and Extension

- The extension automatically registers standardized helpers (`entity`, `entity_list`), and provides dynamic property/task creation using method dispatch.
- The property tasks allow both single and list-based computation.
- Property, entity, and list tasks can have aliases bound as "property aliases" for flexibility and code reuse.
- Annotated arrays or entity sets can use the same API and idioms as single entities.

### Implementation Details

- Uses delegation, helpers, and Ruby metaprogramming (defining singleton methods and property aliases) to wrap entity logic in tasks.
- The module's structure supports downstream integration with documentation, task discovery, and provenance tools.

### Edge Case Handling

- List tasks properly handle `Step` inputs (i.e., loaded lazily), ensuring compatibility with workflow-wide provenance and caching.
- Mixing of entity annotations, options, and input defaults is explicitly managed.
- Property names are automatically derived and de-prefixed to reduce boilerplate.

---

**See Also:**  
- [Workflow Main Documentation](#workflow)
- [Test cases in `test/scout/workflow/test_entity.rb`] for further patterns and behaviors.
