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
      Thread.new(Thread.current) do |parent|
        begin
          consume_stream(io, false, into, into_close)
        rescue Exception
          parent.raise $!
        end
      end
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

        begin
          while c = io.readpartial(BLOCK_SIZE)
            into << c if into
          end
        rescue EOFError
        end

        io.join if io.respond_to? :join
        io.close unless io.closed?
        into.close if into and into_close and not into.closed?
        into.join if into and into_close and into.respond_to?(:joined?) and not into.joined?
        block.call if block_given?

        #Log.medium "Done consuming stream #{Log.fingerprint io}"
      rescue Aborted
        Log.medium "Consume stream aborted #{Log.fingerprint io}"
        io.abort if io.respond_to? :abort
        #io.close unless io.closed?
        FileUtils.rm into_path if into_path and File.exist? into_path
      rescue Exception
        Log.medium "Exception consuming stream: #{Log.fingerprint io}: #{$!.message}"
        io.abort $! if io.respond_to? :abort
        FileUtils.rm into_path if into_path and File.exist? into_path
        raise $!
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
              while block = content.read(BLOCK_SIZE)
                f.write block
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
          Log.exception $!
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
end
