module Workflow
  def self.name2clean_name(name)
    name.reverse.partition("_").last.reverse
  end

  def self.queue_job(file)
    workflow, task, name = file.split("/").values_at(-3, -2, -1) if file
    workflow = Workflow.require_workflow workflow

    if Open.directory?(file) || Open.size(file) > 0
      clean_name = name2clean_name name
      clean_name = nil if clean_name == Task::DEFAULT_NAME
      if ! Open.directory?(file) && ! File.exist?(file)
        TmpFile.with_file do |tmp|
          Open.cp file, tmp
          inputs = workflow.tasks[task].load_inputs(tmp)
          workflow.job(task, clean_name, inputs)
        end
      else
        inputs = workflow.tasks[task].load_inputs(file)
        workflow.job(task, clean_name, inputs)
      end
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
