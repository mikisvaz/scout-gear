module Open
  BLOCK_SIZE = 1024

  class << self
    attr_accessor :sensible_write_lock_dir
    
    def sensible_write_lock_dir
      @sensible_write_lock_dir ||= Path.setup("tmp/sensible_write_locks").find
    end
  end

  class << self
    attr_accessor :sensible_write_dir
    def sensible_write_dir
      @sensible_write_dir ||= Path.setup("tmp/sensible_write").find
    end
  end

  def self.consume_stream(io, in_thread = false, into = nil, into_close = true, &block)
    return if Path === io
    return unless io.respond_to? :read 

    if io.respond_to? :closed? and io.closed?
      io.join if io.respond_to? :join
      return
    end

    if in_thread
      consumer_thread = Thread.new(Thread.current) do |parent|
        Thread.current["name"] = "Consumer #{Log.fingerprint io}"
        Thread.current.report_on_exception = false
        consume_stream(io, false, into, into_close)
      end
      io.threads.push(consumer_thread) if io.respond_to?(:threads)
      consumer_thread
    else
      if into
        Log.medium "Consuming stream #{Log.fingerprint io} -> #{Log.fingerprint into}"
      else
        Log.medium "Consuming stream #{Log.fingerprint io}"
      end

      begin
        into = into.find if Path === into

        if String === into 
          dir = File.dirname(into)
          Open.mkdir dir unless File.exist?(dir)
          into_path, into = into, File.open(into, 'w') 
        end
        
        into.sync = true if IO === into
        into_close = false unless into.respond_to? :close
        io.sync = true

        Log.high "started consuming stream #{Log.fingerprint io}"
        begin
          while c = io.readpartial(BLOCK_SIZE)
            into << c if into
          end
        rescue EOFError
        end

        io.join if io.respond_to? :join
        io.close unless io.closed?
        into.join if into and into_close and into.respond_to?(:joined?) and not into.joined?
        into.close if into and into_close and not into.closed?
        block.call if block_given?

        Log.high "Done consuming stream #{Log.fingerprint io} into #{into_path || into}"
      rescue Aborted
        Log.high "Consume stream Aborted #{Log.fingerprint io} into #{into_path || into}"
        io.abort $! if io.respond_to? :abort
        into.close if into.respond_to?(:closed?) && ! into.closed?
        FileUtils.rm into_path if into_path and File.exist?(into_path)
      rescue Exception
        Log.high "Consume stream Exception reading #{Log.fingerprint io} into #{into_path || into} - #{$!.message}"
        exception = io.stream_exception || $!
        io.abort exception if io.respond_to? :abort
        into.close if into.respond_to?(:closed?) && ! into.closed?
        into_path = into if into_path.nil? && String === into
        if into_path and File.exist?(into_path)
          FileUtils.rm into_path 
        end
        raise exception
      end
    end
  end

  def self.sensible_write(path, content = nil, options = {}, &block)
    force = IndiferentHash.process_options options, :force

    if File.exist?(path) and not force
      Open.consume_stream content 
      return
    end

    lock_options = IndiferentHash.pull_keys options.dup, :lock
    lock_options = lock_options[:lock] if Hash === lock_options[:lock]
    tmp_path = TmpFile.tmp_for_file(path, {:dir => Open.sensible_write_dir})
    tmp_path_lock = TmpFile.tmp_for_file(path, {:dir => Open.sensible_write_lock_dir})

    tmp_path_lock = nil if FalseClass === options[:lock]

    Open.lock tmp_path_lock, lock_options do

      if File.exist? path and not force
        Log.warn "Path exists in sensible_write, not forcing update: #{ path }"
        Open.consume_stream content 
      else
        FileUtils.mkdir_p File.dirname(tmp_path) unless File.directory? File.dirname(tmp_path)
        FileUtils.rm_f tmp_path if File.exist? tmp_path
        begin

          case
          when block_given?
            File.open(tmp_path, 'wb', &block)
          when String === content
            File.open(tmp_path, 'wb') do |f| f.write content end
          when (IO === content or StringIO === content or File === content)
            Open.write(tmp_path) do |f|
              f.sync = true
              begin
                while block = content.readpartial(BLOCK_SIZE)
                  f.write block
                end 
              rescue EOFError
              end
            end
          else
            File.open(tmp_path, 'wb') do |f|  end
          end

          begin
            Misc.insist do
              Open.mv tmp_path, path, lock_options
            end
          rescue Exception
            raise $! unless File.exist? path
          end

          Open.touch path if File.exist? path
          content.join if content.respond_to?(:join) and not Path === content and not (content.respond_to?(:joined?) && content.joined?)

          Open.notify_write(path) 
        rescue Aborted
          Log.medium "Aborted sensible_write -- #{ Log.reset << Log.color(:blue, path) }"
          content.abort if content.respond_to? :abort
          Open.rm path if File.exist? path
        rescue Exception
          exception = (AbortedStream === content and content.exception) ? content.exception : $!
          Log.medium "Exception in sensible_write: [#{Process.pid}] #{exception.message} -- #{ Log.color :blue, path }"
          content.abort if content.respond_to? :abort
          Open.rm path if File.exist? path
          raise exception
        rescue
          raise $!
        ensure
          FileUtils.rm_f tmp_path if File.exist? tmp_path
          if Lockfile === lock_options[:lock] and lock_options[:lock].locked?
            lock_options[:lock].unlock
          end
        end
      end
    end
  end

  PIPE_MUTEX = Mutex.new

  OPEN_PIPE_IN = []
  def self.pipe
    OPEN_PIPE_IN.delete_if{|pipe| pipe.closed? }
    res = PIPE_MUTEX.synchronize do
      sout, sin = IO.pipe
      OPEN_PIPE_IN << sin

      [sout, sin]
    end
    Log.debug{"Creating pipe #{[Log.fingerprint(res.last), Log.fingerprint(res.first)] * " => "}"}
    res
  end

  def self.with_fifo(path = nil, clean = true, &block)
    begin
      erase = path.nil?
      path = TmpFile.tmp_file if path.nil?
      File.rm path if clean && File.exist?(path)
      File.mkfifo path
      yield path
    ensure
      FileUtils.rm path if erase && File.exist?(path)
    end
  end
  
  def self.release_pipes(*pipes)
    PIPE_MUTEX.synchronize do
      pipes.flatten.each do |pipe|
        pipe.close unless pipe.closed?
      end
    end
  end

  def self.purge_pipes(*save)
    PIPE_MUTEX.synchronize do
      OPEN_PIPE_IN.each do |pipe|
        next if save.include? pipe
        pipe.close unless pipe.closed?
      end
    end
  end

  def self.open_pipe(do_fork = false, close = true)
    raise "No block given" unless block_given?

    sout, sin = Open.pipe

    if do_fork

      #parent_pid = Process.pid
      pid = Process.fork {
        purge_pipes(sin)
        sout.close
        begin

          yield sin
          sin.close if close and not sin.closed? 

        rescue Exception
          Log.exception $!
          #Process.kill :INT, parent_pid
          Kernel.exit!(-1)
        end
        Kernel.exit! 0
      }
      sin.close

      ConcurrentStream.setup sout, :pids => [pid]
    else

      ConcurrentStream.setup sin, :pair => sout
      ConcurrentStream.setup sout, :pair => sin

      thread = Thread.new do 
        Thread.current["name"] = "Pipe input #{Log.fingerprint sin} => #{Log.fingerprint sout}"
        Thread.current.report_on_exception = false
        begin
          
          yield sin

          sin.close if close and not sin.closed? and not sin.aborted?
        rescue Aborted
          Log.medium "Aborted open_pipe: #{$!.message}"
          raise $!
        rescue Exception
          Log.medium "Exception in open_pipe: #{$!.message}"
          begin
            sout.threads.delete(Thread.current)
            sout.pair = []
            sout.abort($!) if sout.respond_to?(:abort)
            sin.threads.delete(Thread.current)
            sin.pair = []
            sin.abort($!) if sin.respond_to?(:abort)
          ensure
            raise $!
          end
        end
      end

      sin.threads = [thread]
      sout.threads = [thread]
    end

    sout
  end

  def self.tee_stream_thread_multiple(stream, num = 2)
    in_pipes = []
    out_pipes = []
    num.times do 
      sout, sin = Open.pipe
      in_pipes << sin
      out_pipes << sout
    end

    filename = stream.filename if stream.respond_to? :filename

    splitter_thread = Thread.new(Thread.current) do |parent|
      begin
        Thread.current["name"] = "Splitter #{Log.fingerprint stream}"
        Thread.current.report_on_exception = false

        skip = [false] * num
        begin
          while block = stream.readpartial(BLOCK_SIZE)

            in_pipes.each_with_index do |sin,i|
              begin 
                sin.write block
              rescue IOError
                Log.warn("Tee stream #{i} #{Log.fingerprint stream} IOError: #{$!.message} (#{Log.fingerprint sin})");
                skip[i] = true
              rescue
                Log.warn("Tee stream #{i} #{Log.fingerprint stream} Exception: #{$!.message} (#{Log.fingerprint sin})");
                raise $!
              end unless skip[i] 
            end
          end
        rescue IOError
        end

        stream.join if stream.respond_to? :join
        stream.close unless stream.closed?
        in_pipes.first.close unless in_pipes.first.closed?
      rescue Aborted, Interrupt
        stream.abort if stream.respond_to? :abort
        out_pipes.each do |sout|
          sout.abort if sout.respond_to? :abort
        end
        Log.medium "Tee aborting #{Log.fingerprint stream}"
        raise $!
      rescue Exception
        begin
          stream.abort($!) if stream.respond_to?(:abort) && ! stream.aborted?
          out_pipes.reverse.each do |sout|
            sout.threads.delete(Thread.current)
            begin
              sout.abort($!) if sout.respond_to?(:abort) && ! sout.aborted?
            rescue
            end
          end
          in_pipes.each do |sin|
            sin.close unless sin.closed?
          end
          Log.medium "Tee exception #{Log.fingerprint stream}"
        rescue
          Log.exception $!
        ensure
          in_pipes.each do |sin|
            sin.close unless sin.closed?
          end
          raise $!
        end
      end
    end


    out_pipes.each do |sout|
      ConcurrentStream.setup sout, :threads => splitter_thread, :filename => filename, :pair => stream
    end
    splitter_thread.wakeup until splitter_thread["name"]

    main_pipe = out_pipes.first
    main_pipe.autojoin = true

    main_pipe.callback = Proc.new do 
      stream.join if stream.respond_to? :join
      in_pipes[1..-1].each do |sin|
        sin.close unless sin.closed?
      end
    end

    out_pipes
  end

  def self.tee_stream_thread(stream)
    tee_stream_thread_multiple(stream, 2)
  end

  def self.tee_stream(stream)
    tee_stream_thread(stream)
  end
end
