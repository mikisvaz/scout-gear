require_relative 'parser'
module TSV
  def self.traverse_add(into, res)
    case into
    when TSV::Dumper
      into.add *res
    when TSV, Hash
      key, value = res
      into[key] = value
    end
  end

  def self.traverse(obj, into: nil, cpus: nil, bar: nil, **options, &block)
    case obj
    when TSV
      self.traverse(obj.stream, into: into, cpus: cpus, bar: bar, **options, &block)
    when String
      f = Open.open(obj)
      self.traverse(f, into: into, cpus: cpus, bar: bar, **options, &block)
    when Step
      self.traverse(obj.get_stream, into: into, cpus: cpus, bar: bar, **options, &block)
    when IO
      if into
        into_thread = Thread.new do 
          Thread.current.report_on_exception = false
          Thread.current["name"] = "Traverse into"
          TSV.parse obj, **options do |k,v|
            begin
              res = block.call k, v
              traverse_add into, res
            rescue
              into.abort $!
            end
            nil
          end
          into.close if into.respond_to?(:close)
        end
        Thread.pass until into_thread
        into
      else
        TSV.parse obj, **options do |k,v|
          block.call k, v
          nil
        end
      end
    end
  end
end
