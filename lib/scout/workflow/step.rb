require_relative '../path'
require_relative '../persist'
require_relative 'step/info'
require_relative 'step/load'
require_relative 'step/file'
require_relative 'step/dependencies'
require_relative 'step/provenance'
require_relative 'step/config'
require_relative 'step/progress'

class Step 

  attr_accessor :path, :inputs, :dependencies, :id, :task, :tee_copies
  def initialize(path, inputs = nil, dependencies = nil, id = nil, &task) 
    @path = path
    @inputs = inputs
    @dependencies = dependencies
    @id = id
    @task = task
    @mutex = Mutex.new
    @tee_copies = 1
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

  def clean_name
    return @id if @id
    return info[:clean_name] if info.include? :clean_name
    return m[1] if m = name.match(/(.*?)(?:_[a-z0-9]{32})?(?:\..*)?/)
    return name.split(".").first
  end

  def task_name
    @task_name ||= @task.name if @task.respond_to?(:name)
  end

  def workflow
    @task.workflow if @task
  end

  def exec
    @result = self.instance_exec(*inputs, &task)
  end

  attr_reader :result
  def run
    return @result || self.load if done?
    prepare_dependencies
    run_dependencies
    @result = Persist.persist(name, type, :path => path, :tee_copies => tee_copies) do
      begin
        clear_info
        merge_info :status => :start, :start => Time.now,
          :pid => Process.pid, :pid_hostname => ENV["HOSTNAME"], 
          :inputs => inputs, :type => type,
          :dependencies => dependencies.collect{|d| d.path }

        @result = exec
        @result = @result.stream if @result.respond_to?(:stream)
        @result
      rescue Exception => e
        merge_info :status => :error, :exception => e, :end => Time.now
        raise e
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
    @result
  end

  def done?
    Open.exist?(path)
  end

  def streaming?
    @take_stream || IO === @result || StringIO === @result 
  end

  def stream
    synchronize do
      if streaming? && ! @result.nil?
        if @result.next
          Log.debug "Taking result #{Log.fingerprint @result} next #{Log.fingerprint @result.next}"
        else
          Log.debug "Taking result #{Log.fingerprint @result}"
        end
        @take_stream, @result = @result, @result.next
        @take_stream
      elsif done?
        Open.open(self.path)
      else
        if running?
          nil
        else
          exec
        end
      end
    end
  end

  def consume_all_streams
    threads = [] 
    while @result && streaming? && stream = self.stream
      threads << Open.consume_stream(stream, true)
    end
    threads.each{|t| t.join }
  end

  def join
    consume_all_streams
    self
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
    Open.rm_rf files_dir if Open.exist?(files_dir)
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
      rec_dep = dep.step(task_name)
      return rec_dep if rec_dep
    end
    nil
  end

  def short_path
    Scout.identify @path
  end

  def digest_str
    "Step: " + short_path
  end

  def fingerprint
    digest_str
  end
end
