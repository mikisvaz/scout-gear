# Cookbook

Practical recipes combining multiple scout-gear subsystems. Every snippet
below was executed during the documentation audit; where a call has
surprising corners, the recipe says so.

## Table of contents

1. [Build a gene expression workflow](#build-a-gene-expression-workflow)
2. [Process a large TSV with parallel traversal](#process-a-large-tsv-with-parallel-traversal)
3. [Join two datasets and translate identifiers](#join-two-datasets-and-translate-identifiers)
4. [Query a knowledge base for pathway members](#query-a-knowledge-base-for-pathway-members)
5. [Persist a processed dataset for reuse](#persist-a-processed-dataset-for-reuse)
6. [Stream results from one task to another](#stream-results-from-one-task-to-another)
7. [Run a workflow on an HPC cluster](#run-a-workflow-on-an-hpc-cluster)

---

## Build a gene expression workflow

**Goal**: Build a workflow that reads expression data, normalizes it, and
flags significant genes.

```ruby
module ExpressionAnalysis
  extend Workflow
  self.name = "ExpressionAnalysis"

  input :data_file, :file, "Expression data TSV"
  input :threshold, :float, "Significance threshold", 0.05
  task :significant_genes => :tsv do |data_file, threshold|
    data = TSV.open(data_file, type: :double, persist: true)

    # Use the traverse API for streaming transform. `into:` takes a
    # concrete object you prepared, not a symbol; `unnamed: false` keeps
    # the NamedArray annotation on the values so they can be indexed by
    # field name.
    result = TSV.setup({}, type: :double, key_field: data.key_field,
                       fields: data.fields)
    TSV.traverse(data, into: result, unnamed: false) do |gene, values|
      pval = values["pvalue"].first.to_f
      next nil if pval >= threshold
      [gene, values]
    end
    result
  end
end
```

**Run it**:
```ruby
job = ExpressionAnalysis.job(:significant_genes, data_file: "expr.tsv", threshold: 0.01)
job.run.load
```

**Key points**:
- `persist: true` avoids re-parsing the TSV on repeated runs.
- `TSV.traverse` fills the object you pass as `into:` without loading
  everything into memory — build the result TSV yourself and return it
  from the task. (A symbol such as `into: :tsv` is *not* a target; see
  the `into:` note in the parallel-traversal recipe below.)
- The job result is cached automatically by the workflow engine.

---

## Process a large TSV with parallel traversal

**Goal**: Apply an expensive computation to every row of a large TSV using
4 CPU cores.

```ruby
tsv = TSV.open("large_dataset.tsv", type: :list, persist: true)

result = {}
TSV.traverse(tsv, into: result, cpus: 4) do |key, values|
  score = expensive_score_function(values)
  [key, [score]]
end
```

**Key points**:
- `cpus: 4` forks 4 worker processes.
- The block must be Marshal-serializable (no file handles, IO, or Procs).
- Each worker gets a copy of the TSV (via fork), so memory is duplicated.
  If memory is a concern, use streaming instead.
- `into:` must be a **concrete object** (`Hash`, `TSV`, `Array`, `Set`,
  `IO`, a `TSV::Dumper`, a `Path`, or the symbol `:stream`). A symbol
  such as `:tsv` is *not* a target — nothing is collected and the symbol
  comes back unchanged, so build the TSV yourself and pass it as `into:`.
- Passing `cpus: 1` (or omitting `cpus`) disables forking entirely.

---

## Join two datasets and translate identifiers

**Goal**: Attach gene names to a dataset that uses Ensembl IDs, using an
identifier file.

An identifier file is an ordinary TSV whose **header field names are the
identifier formats** it maps between — for instance a file whose header is
`#Ensembl Gene ID,Associated Gene Name`. The pair of formats served is
decided when the translation happens, not when the file is named: one file
can serve any direction between its columns.

```ruby
# Identifier file: header field names ARE the formats
#   #Ensembl Gene ID,Associated Gene Name
#   ENSG00000141510,GENE1
ids = TSV.open("identifiers")

# Main dataset: Ensembl Gene IDs with expression values
main = TSV.open("expression_ensembl.tsv")

# Attach gene names; keys do not overlap, so `attach` builds a
# translation index from the identifier file
result = main.attach(ids, fields: ["Associated Gene Name"])
```

**Key points**:
- When the tables' keys do not match, `attach` builds a translation index
  from the `identifiers:` option, both tables, and their identifier files
  (including an `identifiers` entry next to the file's directory).
- To translate an existing column instead, use
  `tsv.translate("Source Gene (Associated Gene Name)", "Ensembl Gene ID")`.
  A parenthesized header keeps its label and swaps its format:
  `Source Gene (Associated Gene Name)` becomes
  `Source Gene (Ensembl Gene ID)`.
- The result is a new TSV with the requested column appended.

See [Working with Entities](WorkingWithEntities.md) for how entity types
declare identifier files, and [Processing Tabular
Data](ProcessingTabularData.md) for the full translation mechanics.

---

## Query a knowledge base for pathway members

**Goal**: Use a KnowledgeBase to find all genes in a specific pathway, then
find all drugs targeting those genes' proteins.

```ruby
kb = KnowledgeBase.new("Research")

# Register associations
kb.register :pathway, "pathway_gene.tsv",
  source: "Pathway ID=~Pathway", target: "Ensembl Gene ID=~Gene"
kb.register :geneprotein, "gene_protein.tsv",
  source: "Ensembl Gene ID=~Gene", target: "Protein ID=~Protein"
kb.register :drugtarget, "drug_target.tsv",
  source: "Protein ID=~Protein", target: "Drug ID=~Drug"

drugs = kb.traverse([
  "hsa00010 pathway ?gene",
  "?gene geneprotein ?protein",
  "?protein drugtarget ?drug"
])[1].flatten.compact.uniq
```

**Key points**:
- Each rule is a separate string in the rules array; `kb.traverse` takes
  an Array of rules (a bare String raises
  `NoMethodError: undefined method 'each' for an instance of String`),
  and returns `[assignments, paths]`.
- `?gene`, `?protein`, `?drug` are wildcards bound by the earlier rule
  and carried forward, which is what chains the three associations.
- The assignments Hash gives the bound ids (`result[0]['?drug']`); the
  paths array gives the per-rule match chains. A rule that matches
  nothing contributes nothing to `assignments` for its own wildcard.

---

## Persist a processed dataset for reuse

**Persisting an index**

```ruby
# Build a point index and persist it
index = TSV.index(
  TSV.open("genes.tsv"),
  target: "Gene Name",
  persist: true
)
```

**Using Persist.persist for custom computations**

```ruby
result = Persist.persist("my_computation", :HDB, prefix: "v2") do |filename|
  data = TSV.open("source.tsv")
  data.process { |k, v| transform(v) }
end
```

**Key points**:
- `persist: true` stores the result in a database under `var/databases/`.
- Changing the prefix (e.g., `v1` → `v2`) forces recomputation.
- The block only executes when the cache is invalid.

---

## Stream results from one task to another

**Goal**: Have a downstream task consume a dependency's output as a stream,
without materializing it in memory.

```ruby
module Pipeline
  extend Workflow
  self.name = "Pipeline"

  input :source_file, :file, "Source data"
  task :produce_stream => :tsv do |source_file|
    TSV.open(source_file, type: :list)
  end

  dep :produce_stream, compute: :stream
  task :consume_stream => :tsv do
    stream = step(:produce_stream).load
    result = TSV.setup({}, type: :list, key_field: stream.key_field,
                       fields: stream.fields)
    TSV.traverse(stream, into: result) do |key, values|
      [key, values.map { |v| v.to_i * 2 }]
    end
    result
  end
end
```

**Key points**:
- `compute: :stream` tells the workflow engine to pass the dependency's
  output as a stream rather than materializing it.
- The streamed dependency is **not** handed to the task block as an
  argument; load it with `step(:produce_stream).load`.
- Use the class method `TSV.traverse(stream, into: result)` — the
  instance method has no `into:` keyword — and pass a concrete target.
- This is deadlock-safe because the traversal uses pipes and threads.

---

## Run a workflow on an HPC cluster

**Goal**: Submit workflow jobs to a SLURM cluster.

Rules are provided as scout configuration, typically in YAML files under
`~/.scout/etc/batch`:

```yaml
ExpressionAnalysis:
  defaults:
    time: 2h
    queue: normal
  significant_genes:
    task_cpus: 4
    time: 2h
    mem: 8G
```

`Workflow::Scheduler.process_job` then submits each job with those batch
options; the engine (SLURM by default, `LSF`/`PBS` also built in) is
chosen by the `system` config key or `BATCH_SYSTEM`.

**Key points**:
- Rules specify resources per task (and `defaults` per workflow).
- The scheduler supports SLURM, PBS, and LSF.
- Singularity containers can be specified for reproducibility
  (`contain`/`sync` options).
- See [HPC / Batch Execution](HPCBatchExecution.md) for the full option
  list, job chains, and the `scout batch` CLI.

---

## See also

- [Building Workflows](BuildingWorkflows.md)
- [Processing Tabular Data](ProcessingTabularData.md)
- [Working With Entities](WorkingWithEntities.md)
- [Managing Relationships](ManagingRelationships.md)
- [Running Parallel Work](RunningParallelWork.md)
- [Caching Data](CachingData.md)
- [HPC / Batch Execution](HPCBatchExecution.md)
