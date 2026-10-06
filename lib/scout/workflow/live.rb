require 'fileutils'

module LiveWorkflow
  SHARE_SUBDIRS = %w[tasks helpers entities entity_properties].freeze

  def self.ordered_share_files(workflow)
    root = if workflow.respond_to?(:libdir) && workflow.libdir
             File.expand_path(workflow.libdir.to_s)
           elsif workflow.respond_to?(:name) && workflow.name.to_s == 'ScoutCoder'
             Scout.root.find(:current)
           else
             return []
           end
    SHARE_SUBDIRS.flat_map do |subdir|
      directory = File.join(root, 'share', subdir)
      next [] unless File.directory?(directory)
      Dir.glob(File.join(directory, '**', '*.rb')).sort_by do |file|
        relative = file.delete_prefix(directory + File::SEPARATOR)
        [relative.count(File::SEPARATOR), relative]
      end
    end
  end

  def self.extended(workflow)
    workflow.load_live_files!
    workflow
  end

  def load_live_files!
    current_workflows = Workflow.workflows.dup
    LiveWorkflow.ordered_share_files(self).each do |file|
      begin
        load file
      rescue Exception
        raise ScoutException, "Error loading #{self.name} LiveWorkflow file #{Log.fingerprint file}: " + $!.message
      end
    end
    Workflow.workflows.replace(current_workflows)
    self
  end
end
