require_relative '../open'
module Open
  def self.traverse_add(into, res)
    case into
    when TSV::Dumper
      into.add *res
    when TSV, Hash
      key, value = res
      into[key] = value
    end
  end

  #def self.traverse(obj, into: nil, cpus: nil, bar: nil, **options, &block)
  #  case obj
  #  when TSV
  #    obj.traverse options[:key_field], options[:fields], **options do |k,v|
  #      res = yield k, v
  #    end
  #  when String
  #    f = Open.open(obj)
  #    self.traverse(f, into: into, cpus: cpus, bar: bar, **options, &block)
  #  when Step
  #    self.traverse(obj.stream, into: into, cpus: cpus, bar: bar, **options, &block)
  #  when IO
  #    if into && (IO === into || into.respond_to?(:stream) )
  #      into_thread = Thread.new do 
  #        Thread.current.report_on_exception = false
  #        Thread.current["name"] = "Traverse into"
  #        TSV.parse obj, **options do |k,v|
  #          begin
  #            res = block.call k, v
  #            traverse_add into, res
  #          rescue
  #            into.abort $!
  #          end
  #          nil
  #        end
  #        into.close if into.respond_to?(:close)
  #      end
  #      Thread.pass until into_thread
  #      into
  #    else
  #      TSV.parse obj, **options do |k,v|
  #        block.call k, v
  #        nil
  #      end
  #    end
  #  end
  #end

  def self.traverse(obj, into: nil, cpus: nil, bar: nil, callback: nil, unnamed: true, **options, &block)

    if into || bar
      orig_callback = callback if callback
      bar = Log::ProgressBar.get_obj_bar(bar, obj)
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
            self.traverse(obj, callback: callback, **options, &block)
            into.close if into.respond_to?(:close)
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
        f = Open.open(obj)
        self.traverse(f, cpus: cpus, callback: callback, **options, &block)
      when Step
        raise obj.exception if obj.error?
        self.traverse(obj.stream, cpus: cpus, callback: callback, **options, &block)
      when IO
        TSV.parse obj, **options do |k,v|
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
      bar.abort($!) if bar
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
