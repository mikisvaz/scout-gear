require_relative '../open'
require_relative '../work_queue'
module Open
  def self.traverse_add(into, res)
    case into
    when defined?(TSV::Dumper) && TSV::Dumper
      into.add *res
    when TSV, Hash
      key, value = res
      into[key] = value
    when Array, Set
      into << res
    when IO, StringIO
      into.puts res
    end
  end

  def self.traverse(obj, into: nil, cpus: nil, bar: nil, callback: nil, unnamed: true, keep_open: false, **options, &block)
    cpus = nil if cpus == 1

    if into == :stream
      sout, sin = Open.pipe
      ConcurrentStream.setup(sout, :pair => sin)
      ConcurrentStream.setup(sin, :pair => sout)
      self.traverse(obj, into: sin, cpus: cpus, bar: bar, callback: callback, unnamed: unnamed, **options, &block)
      return sout
    end

    if into || bar
      orig_callback = callback if callback
      bar = Log::ProgressBar.get_obj_bar(bar, obj) if bar
      bar.init if bar
      callback = proc do |res|
        bar.tick if bar
        traverse_add into, res if into
        orig_callback.call res if orig_callback
      end

      if into.respond_to?(:close)
        into_thread = Thread.new do 
          Thread.current.report_on_exception = false
          Thread.current["name"] = "Traverse into"
          error = false
          begin
            self.traverse(obj, callback: callback, cpus: cpus, unnamed: unnamed, **options, &block)
            into.close if ! keep_open && into.respond_to?(:close)
            bar.remove if bar
          rescue Exception
            into.abort($!) if into.respond_to?(:abort)
            bar.remove($!) if bar
          end
        end
        Thread.pass until into_thread
        return into
      end
    end

    if cpus
      queue = WorkQueue.new cpus do |args|
        block.call *args
      end

      queue.process do |res|
        callback.call res
      end
      
      self.traverse(obj, **options) do |*args|
        queue.write args
      end
      queue.close
      begin
        queue.join
        bar.remove if bar
      rescue
        bar.remove($!) if bar
        raise $!
      end
      return into
    end

    begin
      case obj
      when TSV
        obj.traverse options[:key_field], options[:fields], unnamed: unnamed, **options do |k,v|
          res = block.call(k, v)
          callback.call res if callback
          nil
        end
      when Array
        obj.each do |line|
          res = block.call(line)
          callback.call res if callback
          nil
        end
      when String
        obj = obj.produce_and_find if Path === obj
        f = Open.open(obj)
        self.traverse(f, cpus: cpus, callback: callback, **options, &block)
      when Step
        raise obj.exception if obj.error?
        self.traverse(obj.stream, cpus: cpus, callback: callback, **options, &block)
      when IO
        if options[:type] == :array
          while line = obj.gets
            res = block.call line.strip
            callback.call res if callback
            nil
          end
        else
          TSV.parse obj, **options do |k,v|
            res = block.call k, v
            callback.call res if callback
            nil
          end
        end
      when TSV::Parser
        obj.traverse **options do |k,v|
          res = block.call k, v
          callback.call res if callback
          nil
        end
      else
        TSV.parse obj, **options do |k,v|
          res = block.call k, v
          callback.call res if callback
          nil
        end
      end
      bar.remove if bar
    rescue
      bar.error if bar
      raise $!
    end

    into
  end
end

module TSV
  def self.traverse(*args, **kwargs, &block)
    Open.traverse(*args, **kwargs, &block)
  end
end
