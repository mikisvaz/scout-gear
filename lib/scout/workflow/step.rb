require_relative '../path'
require_relative '../persist'
require_relative 'step/info'

class Step 

  attr_accessor :path, :inputs, :dependencies, :task
  def initialize(path, inputs = nil, dependencies = [], &task) 
    @path = path
    @inputs = inputs
    @dependencies = dependencies
    @task = task
  end

  attr_accessor :type
  def type
    @type ||= @task.respond_to?(:type) ? @task.type : nil
  end

  def name
    @name ||= File.basename(@path)
  end

  def task_name
    @task_name ||= @task.name if @task.respond_to?(:name)
  end

  def exec
    self.instance_exec(*inputs, &task)
  end

  attr_reader :result
  def run
    @result = Persist.persist(name, type, :path => path) do
      begin
        merge_info :status => :start, :start => Time.now,
          :pid => Process.pid, :pid_hostname => ENV["HOSTNAME"], 
          :inputs => inputs,
          :dependencies => dependencies.collect{|d| d.path }

        dependencies.each{|dep| dep.run }
        @result = exec
      ensure
        if streaming?
          ConcurrentStream.setup(@result) do
            merge_info :status => :done, :end => Time.now
          end
          log :streaming
        else
          merge_info :status => :done, :end => Time.now
        end
      end
    end
  end

  def done?
    Open.exist?(path)
  end

  def streaming?
    IO === @result || StringIO === @result
  end

  def join
    if streaming?
      Open.consume_stream(@result, false) 
      @result = nil
    end
  end

  def produce
    run
    join
  end

  def load
    return @result unless @result.nil? || streaming?
    join
    done? ? Persist.load(path, type) : exec
  end

  def clean
    FileUtils.rm path.find if path.exist?
  end

  def step(task_name)
    dependencies.each do |dep|
      return dep if dep.task_name == task_name
    end
    nil
  end

  def digest_str
    path
  end
end
