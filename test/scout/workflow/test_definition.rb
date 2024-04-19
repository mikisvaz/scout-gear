require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestWorkflowDefinition < Test::Unit::TestCase
  def test_function_task
    wf = Workflow.annonymous_workflow do
      self.name = "StringLength"
      def self.str_length(s)
        s.length
      end

      input :string, :string
      task :str_length => :integer
    end
    assert_equal 5, wf.job(:str_length, :string => "12345").run
  end

  def test_as_jobname
    wf = Workflow.annonymous_workflow do
      self.name = "CallName"
      input :name, :string, "Name to call", nil, :jobname => true
      task :call_name => :string do |name|
        "Hi #{name}"
      end
    end
    assert_equal "Hi Miguel", wf.job(:call_name, "Miguel").run
    assert_equal "Hi Cleia", wf.job(:call_name, "Miguel", name: "Cleia").run
    assert_equal "Miguel", wf.job(:call_name, "Miguel", name: "Cleia").clean_name
    assert_equal "Cleia", wf.job(:call_name, name: "Cleia").clean_name
  end

  def test_task_alias
    wf = Workflow.annonymous_workflow do
      self.name = "CallName"
      input :name, :string, "Name to call", nil, :jobname => true
      task :call_name => :string do |name|
        "Hi #{name}"
      end

      task_alias :call_miguel, self, :call_name, name: "Miguel"
    end

    job = wf.job(:call_miguel)
    assert_equal "Hi Miguel", job.run
  end

  def test_task_alias_remove_dep
    wf = Workflow.annonymous_workflow do
      self.name = "CallName"
      input :name, :string, "Name to call", nil, :jobname => true
      task :call_name => :string do |name|
        "Hi #{name}"
      end

      task_alias :call_miguel, self, :call_name, name: "Miguel"
    end

    old_cache = Scout::Config::CACHE.dup
    Scout::Config.set({:forget_dep_tasks => true, :remove_dep_tasks => true}, 'task:CallName#call_miguel') 
    job = wf.job(:call_miguel)
    dep_path = job.step(:call_name).path
    assert_equal "Hi Miguel", job.run
    refute job.dependencies.any?
    refute Open.exist?(dep_path)
    Scout::Config::CACHE.replace old_cache
    assert_include job.archived_info, dep_path
    assert_equal :done, job.archived_info[dep_path][:status]
  end
end

