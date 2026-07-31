# Cookbook

Practical recipes combining multiple scout-gear subsystems.

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
  task :significant_genes => :tsv do
    data = TSV.open(input[:data_file], type: :double, persist: true)

    # Use the traverse API for streaming transform
    data.traverse(:key, into: :tsv) do |gene, values|
      pval = values["pvalue"].first.to_f
      next nil if pval >= input[:threshold]
      [gene, values]
    end
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
- `traverse` with `into: :tsv` produces a new TSV without loading
  everything into memory.
- The job result is cached automatically by the workflow engine.

---

## Process a large TSV with parallel traversal

**Goal**: Apply an expensive computation to every row of a large TSV using
4 CPU cores.

```ruby
tsv = TSV.open("large_dataset.tsv", type: :list, persist: true)

result = tsv.traverse(:key, into: :tsv, cpus: 4) do |key, values|
  score = expensive_score_function(values)
  [key, [score]]
end
```

**Key points**:
- `cpus: 4` forks 4 worker processes.
- The block must be Marshal-serializable (no file handles, IO, or Procs).
- Each worker gets a copy of the TSV (via fork), so memory is duplicated.
  If memory is a concern, use streaming instead.

---

## Join two datasets and translate identifiers

**Goal**: Attach gene names to a dataset that uses Ensembl IDs, using a
separate identifier file.

```ruby
# Main dataset: Ensembl Gene IDs with expression values
main = TSV.open("expression_ensembl.tsv", type: :list)

# Identifier file: Ensembl ID → Gene Symbol
id_file = "var/Research/identifiers/Ensembl Gene ID%toAssociated Gene Name"

# Attach gene names by translating identifiers
result = main.attach(
  TSV.open(id_file, type: :single),
  fields: ["Associated Gene Name"]
)
```

**Key points**:
- `attach` auto-detects the matching key if column names overlap.
- If keys don't match directly, provide identifier files to enable
  translation.
- The result is a new TSV with the gene name column appended.

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
  source: "Ensembl Gene ID=~Gene", target: "ErrorProtein ID=~Protein"
kb.register :drugtarget, "drug_target.tsv",
  drugs = kb.traverse("pathway;geneprotein;drugtarget", "hsa00010")
```

**Key points**:
- The traversal path `"pathway;geneprotein;drugtarget"` chains three
  associations.
- Each step takes the output of the previous step as input.
- Results are collected at each step. The final result contains all drugs
  reachable through the path.

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
  task :produce_stream => :tsv do
    TSV.open(input[:source_file], type: :list)
  end

  dep :produce_stream, compute: :stream
  task :consume_stream => :tsv do
    stream = step(:produce_stream).load
    stream.traverse(:key, into: :tsv) do |key, values|
      [key, values.map { |v| v.to_i * 2 }]
    end
  end
  # Force streaming if you want to avoid loading dependency output
end
```

**Key points**:
- `compute: :stream` tells the workflow engine to pass the dependency's
  output as a stream rather than materializing it.
- The downstream task uses `traverse` to process the stream row by row.
- This is deadlock-safe because the traversal uses pipes and threads.

---

## Run a workflow on an HPC cluster

**Goal**: Submit workflow jobs to a SLURM cluster.

```ruby
require 'scout/workflow/deployment/scheduler'

rules = {
  "ExpressionAnalysis" => {
    "significant_genes" => {
      :cpus => 4,
      :time => "2h",
      :mem => "8G",
      :queue => "normal",
    }
  }
}

The `produce` method submits jobs to the cluster.
```

**Key points**:
- Rules specify resources per task.
- The scheduler supports SLURM, PBS, and LSF.
- Singularity containers can be specified for reproducibility.
- See the developer documentation on the
  [Workflow Engine](../developer/WorkflowEngine.md) for more details.

---

## See also

- [Building Workflows](BuildingWorkflows.md)
- [Processing Tabular Data](ProcessingTabularData.md)
- [Working with Entities](WorkingWithEntities.md)
- [Managing Relationships](ManagingRelationships.md)
- [Running Parallel Work](RunningParallelWork.md)
- [Caching Data](CachingData.md)
