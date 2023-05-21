require_relative '../open'
require_relative '../work_queue'

module MultipleResult
  def self.setup(obj)
    obj.extend MultipleResult
    obj
  end
end

module Open
  def self.traverse_add(into, res)
    if Array === res && MultipleResult === res
      res.each do |_res|
        traverse_add into, _res
      end
    else
      case into
      when defined?(TSV::Dumper) && TSV::Dumper
        into.add *res
      when TSV, Hash
        key, value = res
        if into.type == :double
          into.zip_new key, value, insitu: false
        else
          into[key] = value
        end
      when Array, Set
        into << res
      when IO, StringIO
        into.puts res
      end
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
      bar = Log::ProgressBar.get_obj_bar(obj, bar) if bar
      bar.init if bar
      callback = proc do |res|
        bar.tick if bar
        traverse_add into, res if into && ! res.nil?
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
        Thread.pass until into_thread["name"]
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

      queue.join

      begin
        bar.remove if bar
      rescue Exception
        bar.remove($!) if bar
        raise $!
      end
      return into
    end

    begin
      res = case obj
            when TSV
              #obj.traverse options[:key_field], options[:fields], unnamed: unnamed, **options do |k,v,f|
              obj.traverse  unnamed: unnamed, **options do |k,v,f|
                res = block.call(k, v, f)
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
              parser = TSV::Parser.new obj
              parser.traverse **options do |k,v,f|
                res = block.call k,v,f
                callback.call res if callback
                nil
              end
            when TSV::Parser
              obj.traverse **options do |k,v,f|
                res = block.call k, v, f
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

    into || res
  end
end

module TSV
  def self.traverse(*args, **kwargs, &block)
    Open.traverse(*args, **kwargs, &block)
  end

  def self.process_stream(stream, header_hash: "#", &block)
    sout = Open.open_pipe do |sin|
      while line = stream.gets 
        break unless line.start_with?(header_hash)
        sin.puts line
      end
      yield sin, line
    end
  end

  def self.collapse_stream(stream, *args, **kwargs, &block)
    stream = stream.stream if stream.respond_to?(:stream)
    self.process_stream(stream) do |sin, line|
      collapsed = Open.collapse_stream(stream, line: line)
      Open.consume_stream(collapsed, false, sin)
    end
  end

  def collapse_stream(*args, **kwargs, &block)
    TSV.collapse_stream(self.dumper_stream, *args, **kwargs, &block)
  end


end
