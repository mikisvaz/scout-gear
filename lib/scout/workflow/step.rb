require 'scout/path'
require 'scout/persist'
require 'scout/semaphore'
require_relative 'step/info'
require_relative 'step/status'
require_relative 'step/load'
require_relative 'step/file'
require_relative 'step/dependencies'
require_relative 'step/provenance'
require_relative 'step/config'
require_relative 'step/progress'
require_relative 'step/inputs'

class Step 

  attr_accessor :path, :inputs, :dependencies, :id, :task, :tee_copies, :non_default_inputs, :provided_inputs, :compute, :overriden_task, :overriden_workflow, :workflow, :exec_context
  def initialize(path = nil, inputs = nil, dependencies = nil, id = nil, non_default_inputs = nil, provided_inputs = nil, compute = nil, exec_context = nil, &task)
    @path = path
    @inputs = inputs
    @dependencies = dependencies
    @id = id
    @non_default_inputs = non_default_inputs
    @provided_inputs = provided_inputs
    @compute = compute 
    @task = task
    @mutex = Mutex.new
    @tee_copies = 1
    @exec_context = exec_context || self
  end

  def synchronize(&block)
    @mutex.synchronize(&block)
  end

  def inputs
    @inputs ||= begin
                  if info_file && Open.exists?(info_file)
                    inputs = info[:inputs]
                    NamedArray.setup(inputs, info[:input_names]) if inputs && info[:input_names]
                    inputs
                  else
                    []
                  end
                end
  end

  def dependencies
    @dependencies ||= begin
                        if Open.exists?(info_file)
                          info[:dependencies].collect do |path|
                            path = path.last if Array === path
                            Step.load(path)
                          end if info[:dependencies]
                        else
                          []
                        end
                      end
  end

  attr_accessor :type
  def type
    @type ||= (@task.respond_to?(:type) && @task.type) ? @task.type : info[:type]
  end

  def name
    @name ||= File.basename(@path)
  end

  def short_path
    [workflow.to_s, task_name, name] * "/"
  end

  def clean_name
    return @id if @id
    return info[:clean_name] if info.include? :clean_name
    return m[1] if m = name.match(/(.*?)(?:_[a-z0-9]{32})?(?:\..*)?/)
    return name.split(".").first
  end

  def task_name
    @task_name ||= @task.name if @task.respond_to?(:name)
    @task_name ||= info[:task_name] if Open.exist?(info_file)
    @task_name ||= path.split("/")[-2]
  end

  def workflow
    @workflow ||= @task.workflow if Task === @task
    @workflow ||= info[:workflow] if info_file && Open.exist?(info_file)
    @workflow ||= path.split("/")[-3]
  end

  def exec

    if inputs 
      if Task === task
        types = task.inputs.collect{|name,type| type }
        new_inputs = inputs.zip(types).collect{|input,info|  
          type, desc, default, options = info
          next input unless Step === input
          input.join if input.streaming?
          Task.format_input(input.join.path, type, options)
        }
      else
        new_inputs = inputs.collect{|input|  
          Step === input ? input.load : input
        }
      end
      inputs = new_inputs
    end

    @result = begin
                @in_exec = true
                @exec_context.instance_exec(*inputs, &task)
              ensure
                @in_exec = false
              end
  end

  def tmp_path
    @tmp_path ||= begin
                    basename = File.basename(@path)
                    dirname = File.dirname(@path)
                    tmp_path = File.join(dirname, '.' + basename)
                    @path.setup(tmp_path) if Path === @path
                    tmp_path
                  end
  end

  attr_reader :result
  def run(stream = false)
    return @result || self.load if done?
    prepare_dependencies
    run_dependencies
    begin
      @result = Persist.persist(name, type, :path => path, :tee_copies => tee_copies) do
        clear_info
        input_names = (task.respond_to?(:inputs) && task.inputs) ? task.inputs.collect{|name,_| name} : []
        merge_info :status => :start, :start => Time.now,
          :pid => Process.pid, :pid_hostname => Misc.hostname, 
          :task_name => task_name, :workflow => workflow.to_s,
          :inputs => Annotation.purge(inputs), :input_names => input_names, :type => type,
          :dependencies => (dependencies || []) .collect{|d| d.path }

        @exec_result = exec

        if @exec_result.nil? && File.exist?(self.tmp_path) && ! File.exist?(self.path)
          Open.mv self.tmp_path, self.path
        else
          @exec_result = @exec_result.stream if @exec_result.respond_to?(:stream)
        end

        @exec_result

        if (IO === @exec_result || StringIO === @exec_result) && (ENV["SCOUT_NO_STREAM"] == "true" || ! stream)
          Open.sensible_write(self.path, @exec_result)
          @exec_result = nil
        else
          @exec_result
        end
      end
    rescue Exception => e
      merge_info :status => :error, :exception => e, :end => Time.now
      abort_dependencies
      raise e
    ensure
      if ! (error? || aborted?)
        if streaming?
          ConcurrentStream.setup(@result) do
            merge_info :status => :done, :end => Time.now
          end

          @result.abort_callback = proc do |exception|
            if exception.nil? || Aborted === exception || Interrupt === exception
              merge_info :status => :aborted, :end => Time.now
            else
              begin
                merge_info :status => :error, :exception => exception, :end => Time.now
              rescue Exception
                Log.exception $!
              end
            end
          end


          log :streaming
        else
          merge_info :status => :done, :end => Time.now
        end
      end
    end
  end

  def fork(noload = false, semaphore = nil)
    Process.fork do
      clear_info unless present?
      if semaphore
        log :queue, "Queued over semaphore: #{semaphore}"
        ret = ScoutSemaphore.wait_semaphore(semaphore)
        raise SemaphoreInterrupted if ret == -1
        run(noload)
      else
        run(noload)
      end
      join
    end
    grace
    self
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

        return @take_stream
      end
    end

    if done?
      Open.open(self.path)
    else
      if running? || waiting?
        join
        Open.open(self.path)
      else
        exec
      end
    end
  end

  def consume_all_streams
    threads = [] 
    while @result && streaming? && stream = self.stream
      threads << Open.consume_stream(stream, true)
    end

    threads.compact!

    threads.each do |t| 
      begin
        t.join 
      rescue Exception
        threads.compact.each{|t| t.raise(Aborted); t.join }
        raise $!
      end
    end
  end

  def present?
    Open.exist?(path) ||
      Open.exist?(info_file) ||
      Open.exist?(files_dir)
  end

  def grace
    while ! present?
      sleep 0.1
    end
    self
  end

  def terminated?
    ! @in_exec && (done? || error? || aborted?)
  end

  def join
    consume_all_streams
    while @result.nil? && (present? && ! (terminated? || done?))
      sleep 0.1
    end
    raise self.exception if self.exception
    raise "Error in job #{self.path}" if self.error? or self.aborted? 
    self
  end

  def produce(with_fork: false)
    if with_fork
      self.fork
      self.join
    else
      run
    end
    self
  end

  def load
    return @result unless @result.nil? || streaming?
    join
    done? ? Persist.load(path, type) : exec
  end

  def step(task_name)
    task_name = task_name.to_sym
    dependencies.each do |dep|
      return dep if dep.task_name && dep.task_name.to_sym == task_name
      return dep if dep.overriden_task && dep.overriden_task.to_sym == task_name
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

  def task_signature
    [workflow.to_s, task_name] * "#"
  end

  def alias?
    task.alias? if task
  end
end
