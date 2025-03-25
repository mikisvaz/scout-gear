module Workflow
  def self.name2clean_name(name)
    name.reverse.partition("_").last.reverse
  end

  def self.queue_job(file)
    workflow, task, name = file.split("/").values_at(-3, -2, -1) if file
    workflow = Workflow.require_workflow workflow

    if Open.directory?(file)
      clean_name = name2clean_name name
      inputs = workflow.tasks[task].load_inputs(file)
      workflow.job(task, clean_name, inputs)
    else
      workflow.job(task, name)
    end
  end

  def self.unqueue(file, &block)
    Open.lock file do
      job = queue_job(file)
      puts job.run
      Open.rm_rf file
    end
  end
end
