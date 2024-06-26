require_relative 'workflow/definition'
require_relative 'workflow/util'
require_relative 'workflow/task'
require_relative 'workflow/step'
require_relative 'workflow/documentation'
require_relative 'workflow/usage'
require_relative 'workflow/deployment'
require_relative 'workflow/exceptions'

require 'scout/resource'
require 'scout/resource/scout'

module Workflow
  class << self
    attr_accessor :workflows, :main, :workflow_dir, :autoinstall, :workflow_repo
    def workflows
      @workflows ||= []
    end

    def workflow_dir
      @workflow_dir || 
        ENV["SCOUT_WORKFLOW_DIR"] || 
        begin 
          workflow_dir_config = Path.setup("etc/workflow_dir")
          if workflow_dir_config.exists?
            Path.setup(workflow_dir_config.read.strip)
          else
            Path.setup('workflows').find(:user)
          end
        end
    end

    def workflow_repo
      @workflow_repo || 
        ENV["SCOUT_WORKFLOW_REPO"] || 
        begin 
          workflow_repo_config = Path.setup("etc/workflow_repo")
          if workflow_repo_config.exists?
            workflow_repo_config.read.strip
          else
            'https://github.com/Scout-Workflows/'
          end
        end
    end

    def autoinstall
      @autoinstall || ENV["SCOUT_WORKFLOW_AUTOINSTALL"] = "true"
    end

  end

  attr_accessor :libdir

  def self.extended(base)
    self.workflows << base
    libdir = Path.caller_lib_dir
    return if libdir.nil?
    base.libdir = Path.setup(libdir).tap{|p| p.resource = base}
  end

  def self.update_workflow_dir(workflow_dir)
    Misc.in_dir(workflow_dir) do
      Log.info "Updating: " + workflow_dir
      `git pull`
      `git submodule init`
      `git submodule update`
    end
  end

  def self.install_workflow(workflow, base_repo_url = nil)
    case
    when File.exist?(workflow)
      update_workflow_dir(workflow)
    else
      Misc.in_dir(self.workflow_dir) do
        Log.info "Installing: " + workflow

        repo_base_url ||= self.workflow_repo


        if repo_base_url.include?(workflow) or repo_base_url.include?(Misc.snake_case(workflow))
          repo = repo_base_url
        else
          begin
            repo = File.join(repo_base_url, workflow + '.git')
            CMD.cmd("wget '#{repo}' -O /dev/null").read
          rescue
            Log.debug "Workflow repo does not exist, trying snake_case: #{ repo }"
            begin
              repo = File.join(repo_base_url, Misc.snake_case(workflow) + '.git')
              CMD.cmd("wget '#{repo}' -O /dev/null").read
            rescue
              raise "Workflow repo does not exist: #{ repo }"
            end
          end
        end

        Log.warn "Cloning #{ repo }"
        Misc.insist do
          `git clone "#{repo}" #{ Misc.snake_case(workflow) }`
          raise unless $?.success?
        end
        Log.warn "Initializing and updating submodules for #{repo}. You might be prompted for passwords."
        Misc.in_dir(Misc.snake_case(workflow)) do
          `git submodule init`
          `git submodule update`
        end
      end
    end
  end

  def self.require_workflow_file(file)
    file = file.find if Path === file
    $LOAD_PATH.unshift(File.join(File.dirname(file), 'lib'))
    load file
  end

  def self.require_workflow(workflow_name_orig)
    first = nil
    workflow_name_orig.split("+").each do |complete_workflow_name|
      self.main = nil

      Persist.memory(complete_workflow_name, prefix: "Workflow") do
        begin
          workflow_name, *subworkflows = complete_workflow_name.split("::")
          workflow_file = workflow_name
          workflow_file = Path.setup('workflows')[workflow_name]["workflow.rb"] unless Open.exists?(workflow_file)
          workflow_file = Path.setup('workflows')[Misc.snake_case(workflow_name)]["workflow.rb"] unless Open.exists?(workflow_file)
          workflow_file = Path.setup('workflows')[Misc.camel_case(workflow_name)]["workflow.rb"] unless Open.exists?(workflow_file)
          if Open.exists?(workflow_file)
            self.main = nil
            require_workflow_file(workflow_file)
          elsif autoinstall
            install_workflow(workflow_name)
            raise TryAgain
          else
            raise "Workflow #{workflow_name} not found"
          end
        rescue TryAgain
          retry
        end
      end

      current = begin
                  Kernel.const_get(complete_workflow_name)
                rescue
                  self.main || workflows.last
                end

      first ||= current
    end
    first
  end

  def job(name, *args)
    task = tasks[name]
    raise TaskNotFound, "Task #{task_name} in #{self.to_s}" if task.nil?
    step = task.job(*args)
    step.extend step_module
    step
  end
end
