# KnowledgeBase

KnowledgeBase is a thin orchestration layer around Association, TSV, Entity and Persist that lets you:

- Register and manage multiple association databases (with per-database options).
- Build and cache normalized TSV databases and pairwise “source~target” indices.
- Annotate, translate and query entities (sources/targets) consistently using configured identifier files and formats.
- Run high-level queries: full sets, subsets, children, parents, neighbours.
- Traverse paths across multiple databases using a tiny DSL with wildcards, lists and conditions.
- Manage entity lists (save/load) and generate human-readable markdown descriptions for databases.

It integrates with:
- Association (database/field normalization and index creation)
- TSV (parsing, indices)
- Entity (formats and translation)
- Persist (caching and persistence)
- SOPT CLI (scout kb …)

Sections:
- Creating and loading a knowledge base
- Registering databases
- Entity options and identifier files
- Databases and indices (open/get)
- Querying (all/subset/children/parents/neighbours)
- Lists (save/load/delete/enumerate)
- Traversal DSL
- Descriptions and markdown docs
- Enrichment
- API quick reference
- CLI: scout kb commands
- Examples

---

## Creating and loading a knowledge base

- Create a new KnowledgeBase pointing to a directory (will store config, indices, databases and lists under it):

```ruby
kb = KnowledgeBase.new(Path.setup("var/kb"), "Hsa") # namespace optional
kb.save
```

- Load a previously saved one:
```ruby
kb = KnowledgeBase.load(:default)      # or KnowledgeBase.load("/path")
```

- Persisted attributes (saved to dir/config):
  - namespace (e.g., species code “Hsa”)
  - registry — mapping of database name => [file or block, options]
  - entity_options — per-entity configuration (e.g., identifier TSVs; default entity parameters)
  - identifier_files — knowledge-base-wide identifier files (used to build translation indices)

Save changes:
```ruby
kb.save
```

---

## Registering databases

Use register to declare databases, associating a name with a TSV source and options:

```ruby
kb.register :brothers, datafile_test(:person).brothers, undirected: true
kb.register :parents,  datafile_test(:person).parents,
            source: "=>Alias", target: "=>Name",
            fields: ["Date"], entity_options: {"Person" => {language: "en"}},
            identifiers: TSV.open(id_file)
```

- file can be:
  - a Path/String (TSV file), or
  - a Proc block that returns a TSV Path/String/TSV (block gets stored as part of the registry).
- Common options (mirrors Association.open/index):
  - :source, :target — field specifications ("Field", "Field=~Header", "Field=>Format", "Field=~Header=>Format")
  - :fields — info field subset to keep (defaults to all others)
  - :identifiers — TSV/Path or array, to help with format translation
  - :namespace — overrides NAMESPACE placeholders in paths
  - :undirected — treat database as undirected (source~target and target~source)
  - :description — human-readable description string (used by kb.description)
  - :entity_options — per-database overrides (merged with kb.entity_options)

Registered names are available via kb.all_databases and kb.include?(name).

---

## Entity options and identifier files

Entity annotation and translation are controlled by:
- kb.entity_options — e.g., { "Person" => { language: "es", identifiers: [path1,path2] } }
- kb.identifier_files — KB-wide extra identifier TSVs (supplement).

Helper:
- kb.define_entity_modules — dynamically defines Entity modules and includes Entity::Identified when entity_options include :identifiers, wiring add_identifiers and default formats.

Entity annotation/translation:
- kb.entity_options_for(type, database_name=nil) merges global entity_options for type and any per-database overrides.
- kb.annotate(values, entity_type_name, database_name=nil) wraps values in Entity with appropriate :format and options.
- kb.translate(entities, entity_type_name) converts to the KB’s configured format if needed.

Entity type discovery:
- kb.source_type(name) / kb.target_type(name) — returns Entity module for source/target formats (using Entity.formats).

---

## Databases and indices (open/get)

- kb.get_database(name, options = {}) → persisted TSV (Association.database) for that name:
  - Builds and caches a normalized TSV (key_field = source, fields = [target, info...]).
  - Respects registry options, kb.namespace, entity_options and identifiers.
  - Stores under dir/<name>_<digest>.database by default.

- kb.get_index(name, options = {}) → persisted index TSV (Association.index):
  - BDB-backed list TSV with keys “source~target” and values (info fields).
  - Stores under dir/<name>_<digest> (and <name>_<digest>.reverse for reverse index).
  - Exposes fields source_field, target_field, undirected.

Introspection:
- kb.fields(name)            # => info field names of index
- kb.pair(name)              # => [source_field, target_field, (optional umarker)]
- kb.source(name) / kb.target(name)
- kb.undirected(name)        # => boolean

Identifier translation indices:
- kb.source_index(name) — TSV.translation_index(..., target = source(name))
- kb.target_index(name) — TSV.translation_index(..., target = target(name))
- kb.identify_source(name, value|list|:all) — translate by source index
- kb.identify_target(name, value|list|:all) — translate by target index
- kb.identify(name, entity) — try source index first, then target

---

## Querying (all/subset/children/parents/neighbours)

AssociationItem is used to wrap pair keys and expose properties like source_entity and target_entity.

- kb.all(name, options={}) → AssociationItem list
  - Returns all pairs (index.keys), annotated with KB context.

- kb.subset(name, entities_or_options, options={}, &block) → AssociationItem list
  - entities_or_options:
    - :all
    - AnnotatedArray (e.g., list of People) — KB infers a format key in the Hash
    - Hash — e.g., { source: ["Miki"], target: :all } or { "Person" => %w(Miki Isa) }
  - options:
    - identify, identify_source, identify_target — translate input entities through indices
  - Block: filter the resulting AssociationItem list.

- kb.children(name, entity) → AssociationItem list
  - Pairs where entity appears as source. Equivalent to index.match(entity).

- kb.parents(name, entity) → AssociationItem list
  - Pairs where entity appears as target (reverse.match(entity)); annotated with reverse=true.

- kb.neighbours(name, entity) → {children: ..., parents: ...} or {:children => ...} when undirected with same source/target.

Entity typing:
- All methods annotate returned IDs into Entities using kb.annotate and per-database options (so things like Person#language apply).

---

## Lists (save/load/delete/enumerate)

KB ships utilities for storing lists of entities or raw strings under dir/lists:

- kb.save_list(id, list)
  - AnnotatedArray → saved as an Annotation.tsv; plain arrays → saved as newline-separated text (simple).
- kb.load_list(id, entity_type=nil) → AnnotatedArray or Array
  - If entity_type given and typed list not found, falls back to any present.
- kb.lists → { "Person" => [ids...], "simple" => [ids...] }
- kb.delete_list(id, entity_type=nil)

List paths are resolved safely under dir/lists/<EntityType>/<id>.tsv or dir/lists/simple/<id>.

---

## Traversal DSL

Find paths across databases using concise rules with wildcards and conditions:

- kb.traverse(rules, nopaths=false) → [assignments, paths]
  - rules: Array of strings, each a statement or assignment:

Rules syntax:
- Match rule: "<source> <db> <target> [ - <conditions> ]"
  - <source>/<target> term types:
    - literal entity (e.g., "Miki", "001")
    - wildcard "?var" — capture assignment
    - list ":list_id" — use kb.load_list(list_id)
  - <db>: database name; may include “@KB” to qualify; supports wildcard components (see implementation).
  - conditions: space separated tokens:
    - "Field=Value" (exact match via Misc.match_value)
    - "Field" (truthy)

- Assignment rule: "?var =<db> value1,value2,..."
  - If <db> present, identifies values within that DB; otherwise uses the raw names.

- Accumulation block:
  ```
  ?var{
    <rule1>
    <rule2>
  }
  ```
  - Captures results produced inside block into ?var, and resets other temp assignments at block end.

Traverse returns:
- assignments — map of "?vars" to arrays of matched IDs (translated into source/target ids as needed).
- paths — list of paths, each path is a list of AssociationItem pairs; each item has .info and Entity wrappers.

Example:
```ruby
rules = [
  "Miki brothers ?1",
  "?1 parents Domingo"       # find parents of Miki’s siblings who are Domingo
]
entities, paths = kb.traverse(rules)
entities["?1"]              # => ["Isa", ...] (siblings)
paths.first.first.info      # => info hash for first pair
```

---

## Descriptions and markdown docs

- kb.description(:db_name) → tries, in order:
  - registered_options[:description]
  - dir/<db>.md
  - First-level README.md in kb.dir parsed to get per-database chunk (# <db name> sections)
  - Source DB’s README.md (file’s dir) if kb README lacks it

- kb.markdown(:db_name) → generated markdown containing:
  - Title (# DatabaseName)
  - Source and target descriptions (with types)
  - Undirected note if applicable
  - Embedded description (if any)

---

## Enrichment

- kb.enrichment(db_name, entities, options={}) → runs hypergeometric enrichment using rbbt (requires rbbt/rbbt-statistics):
  - Loads get_database(db_name) and converts entities via identify_source
  - Calls database.enrichment(entities, database.fields.first, persist: false)

---

## API quick reference

Construction/persistence:
- KnowledgeBase.new(dir, namespace=nil)
- KnowledgeBase.load(dir | :default)
- kb.save / kb.load

Registry:
- kb.register(name, file=nil, options={}, &block)
- kb.include?(name) → boolean
- kb.all_databases → names
- kb.database_file(name) / kb.registered_options(name)

Entities/identifiers:
- kb.entity_options (Hash), kb.entity_options=(Hash)
- kb.identifier_files (Array), kb.identifier_files+=(Array)
- kb.define_entity_modules
- kb.annotate(values, type, database=nil) → Entity-wrapped
- kb.translate(entities, type) → convert format
- kb.source_type(name) / kb.target_type(name)

Databases/indices:
- kb.get_database(name, options={}) → TSV
- kb.get_index(name, options={}) → TSV (Association::Index)
- kb.fields(name), kb.pair(name), kb.source(name), kb.target(name), kb.undirected(name)

Identifier translation:
- kb.source_index(name), kb.target_index(name)
- kb.identify_source(name, entity), kb.identify_target(name, entity), kb.identify(name, entity)

Queries:
- kb.all(name, options={})
- kb.subset(name, entities_or_options, options={}, &block)
- kb.children(name, entity)
- kb.parents(name, entity)
- kb.neighbours(name, entity) → {:children=>..., :parents=>...} or {:children=>...}

Lists:
- kb.save_list(id, list) / kb.load_list(id, entity_type=nil)
- kb.lists → {type => [ids]} / kb.delete_list(id, entity_type=nil)

Traversal:
- kb.traverse(rules, nopaths=false) → [assignments, paths]

Documentation:
- kb.description(name) / kb.markdown(name)

Utilities:
- kb.info(name) → hash with source, target, types, entity_options, fields, undirected flag

---

## Command Line Interface (scout kb)

The KnowledgeBase CLI lives under scout_commands/kb and is discovered using the Path subsystem. General pattern: scout kb <subcommand> [options] ...

- Configure the knowledge base:
  - scout kb config [options] <name>
    - Options:
      - -kb|--knowledge_base <name_or_:default> (default :default)
      - -i|--identifier_files file1,file2,...
      - -n|--namespace <ns>
    - Saves config to kb.dir/config.

- Register a database:
  - scout kb register [options] <name> <filename>
    - Options:
      - -kb|--knowledge_base
      - -s|--source <spec>
      - -t|--target <spec>
      - -f|--fields field1,field2
      - -n|--namespace <ns>
      - -i|--identifiers <paths_or_ids>
      - -u|--undirected
      - -d|--description <text>
    - File is resolved via Scout.identify; the registry entry is saved.

- Declare entities and set identifiers:
  - scout kb entities [options] <entity> <identifier_files>
    - Appends identifiers (comma-separated) to kb.entity_options[entity][:identifiers].

- Show database information:
  - scout kb show [options] <name>
    - Without name, lists all database names.
    - With name, prints markdown summary and TSV preview (fields/key).

- Query an index:
  - scout kb query [options] <name> <entity>
    - Options:
      - -l|--list (only print keys)
      - -s|--source <spec>, -t|--target <spec>, -n|--namespace, -i|--identifiers
    - entity may be:
      - "X~" (prefix match on source), "~Y" (prefix match on target), "X~Y" (exact), or "X" (prefix match).
    - Prints matches and per-edge info unless --list.

- Lists:
  - scout kb list [options] [<list_name>]
    - Without list_name, prints available lists grouped by entity type and “simple”.
    - With list_name, prints the list contents.

- Traverse:
  - scout kb traverse [options] <traversal>
    - Options:
      - -p|--paths       Only list path edges and their info
      - -e|--entities    Only list wildcard entities
      - -l|--list <var>  Print the matches bound to wildcard ?<var>
      - -ln|--list_name  Save the printed list with a name
    - traversal: comma-separated rules (see Traversal DSL).
    - Output:
      - entities dump (type => values)
      - path edges with info (unless suppressed)
      - In list mode, prints captured list and optionally saves it via save_list.

CLI discovery:
- Running “scout kb” with no subcommand lists available kb subcommands (directories under share/scout_commands/kb).
- The resolver supports nested commands and shows help if a directory is selected.

---

## Examples

Register and query:

```ruby
kb = KnowledgeBase.new tmpdir
kb.register :brothers, datafile_test(:person).brothers, undirected: true
kb.register :parents,  datafile_test(:person).parents

kb.all(:brothers)                 # => ["Miki~Isa", ...]
kb.children(:parents, "Miki")     # => ["Miki~Juan", "Miki~Mariluz"]
kb.parents(:parents, "Domingo")   # => ["Clei~Domingo", ...] (reverse annotated)
```

Typed entities and per-database options:

```ruby
kb.entity_options = { "Person" => { language: "es" } }
kb.register :parents, datafile_test(:person).parents, entity_options: { "Person" => { language: "en" } }

matches = kb.subset(:parents, target: :all, source: ["Miki"])
parents  = matches.target_entity
parents.first.class  # => Person (Entity)
parents.first.language  # => "en" (database override applied)
```

Save/load lists:

```ruby
list = kb.subset(:brothers, :all).target_entity
kb.save_list("bro_and_sis", list)
kb.load_list("bro_and_sis") == list  # => true
kb.lists["Person"]                   # => includes "bro_and_sis"
kb.delete_list("bro_and_sis")
```

Traverse:

```ruby
rules = [
  "Miki brothers ?sib",            # siblings of Miki
  "?sib parents Domingo"           # those with parent Domingo
]
entities, paths = kb.traverse(rules)
entities["?sib"]       # => ["Clei", ...]
paths.first.first.info # => {"Type of parent"=>"mother", "Date"=>"..."}
```

Show descriptions:

```ruby
kb.register :brothers, brothers_file, description: "Sibling relationships."
kb.markdown(:brothers)  # => "# Brothers\n\nSource: Older ...\nTarget: Younger ...\n\nSibling relationships."
```

Enrichment:

```ruby
kb.enrichment(:brothers, %w(Miki Isa), persist: false)
```

---

KnowledgeBase glues together format-aware entity typing, TSV-backed association databases, and flexible traversal/querying, while providing a simple registry and on-disk caching under a single directory. Use it to consolidate relationship data and build rich exploration tools (CLI and programmatic) atop clean source/target semantics.