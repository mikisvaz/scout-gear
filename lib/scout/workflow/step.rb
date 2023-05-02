require_relative '../path'
require_relative '../persist'
require_relative 'step/info'
require_relative 'step/load'

class Step 

  attr_accessor :path, :inputs, :dependencies, :task
  def initialize(path, inputs = nil, dependencies = nil, &task) 
    @path = path
    @inputs = inputs
    @dependencies = dependencies
    @task = task
    @mutex = Mutex.new
  end

  def synchronize(&block)
    @mutex.synchronize(&block)
  end

  def inputs
    @inputs ||= begin
                  if Open.exists?(info_file)
                    info[:inputs]
                  else
                    []
                  end
                end
  end

  def dependencies
    @dependencies ||= begin
                        if Open.exists?(info_file)
                          info[:dependencies].collect do |path|
                            Step.load(path)
                          end
                        else
                          []
                        end
                      end
  end

  attr_accessor :type
  def type
    @type ||= @task.respond_to?(:type) ? @task.type : info[:type]
  end

  def name
    @name ||= File.basename(@path)
  end

  def task_name
    @task_name ||= @task.name if @task.respond_to?(:name)
  end

  def exec
    @result = self.instance_exec(*inputs, &task)
  end

  attr_reader :result
  def run
    return @result || self.load if done?
    dependencies.each{|dep| dep.run unless dep.running? || dep.done? }
    @result = Persist.persist(name, type, :path => path) do
      begin
        merge_info :status => :start, :start => Time.now,
          :pid => Process.pid, :pid_hostname => ENV["HOSTNAME"], 
          :inputs => inputs, :type => type,
          :dependencies => dependencies.collect{|d| d.path }

        exec
      rescue
        merge_info :status => :error, :exception => $!
        raise $!
      ensure
        if ! (error? || aborted?)
          if streaming?
            ConcurrentStream.setup(@result) do
              merge_info :status => :done, :end => Time.now
            end

            @result.abort_callback = proc do |exception|
              if Aborted === exception || Interrupt === exception
                merge_info :status => :aborted, :end => Time.now
              else
                merge_info :status => :error, :exception => exception, :end => Time.now
              end
            end

            log :streaming
          else
            merge_info :status => :done, :end => Time.now
          end
        end
      end
    end
  end

  def done?
    Open.exist?(path)
  end

  def streaming?
    @take_stream || IO === @result || StringIO === @result
  end

  def get_stream
    synchronize do
      if streaming? && ! @take_stream
        Log.debug "Taking stream from result #{Log.color :path, self.path}"
        @take_stream, @result = @result, nil
        @take_stream
      elsif done?
        Open.open(self.path)
      else
        exec
      end
    end
  end

  def join
    stream = synchronize do
      if streaming?
        stream, @result = @result, stream
        stream
      else
        nil
      end
    end
    Open.consume_stream(stream, false) if stream
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
    @take_stream = nil 
    @result = nil
    @info = nil
    @info_load_time = nil
    Open.rm path if Open.exist?(path)
    Open.rm info_file if Open.exist?(info_file)
  end

  def recursive_clean
    dependencies.each do |dep|
      dep.recursive_clean
    end
    clean
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
