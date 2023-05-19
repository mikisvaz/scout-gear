module TSV
  class Transformer
    attr_accessor :unnamed, :dumper

    def initialize(parser, dumper = nil, unnamed: false)
      if TSV::Parser === parser
        @parser = parser
      elsif TSV === parser
        @parser = parser
      else
        @parser = TSV::Parser.new parser
      end
      @unnamed = unnamed
      if dumper.nil?
        @dumper = TSV::Dumper.new(@parser.all_options)
        @dumper.sep = "\t"
      else
        @dumper = dumper
      end
    end

    def fields=(fields)
      @dumper.options[:fields] = fields
    end

    def key_field=(key_field)
      @dumper.options[:key_field] = key_field
    end

    def type=(type)
      @dumper.type = type
    end

    def type
      @dumper.type
    end

    def sep=(sep)
      @dumper.sep = sep
    end

    def include?(*args)
      false
    end

    def key_field
      @dumper.options[:key_field]
    end

    def fields
      @dumper.options[:fields]
    end

    def all_fields
      [key_field] + fields
    end

    def identify_field(name)
      TSV.identify_field key_field, fields, name
    end

    def traverse(*args, **kwargs, &block)
      kwargs[:into] = @dumper
      @dumper.init unless @dumper.initialized
      Open.traverse(@parser, *args, **kwargs) do |k,v|
        NamedArray.setup(v, @parser.fields, k) unless @unnamed
        block.call k, v
      end
    end

    def each(*args, **kwargs, &block)
      kwargs[:into] = @dumper
      @dumper.init unless @dumper.initialized
      Open.traverse(@parser, *args, **kwargs) do |k,v|
        NamedArray.setup(v, @parser.fields, k) unless @unnamed
        block.call k, v
        [k, v]
      end
    end

    def with_unnamed
      begin
        old_unnamed = @unnamed
        @unnamed = true
        yield
      ensure
        @unnamed = old_unnamed
      end
    end

    def []=(key, value)
      @dumper.add key, value
    end

    def stream
      @dumper.stream
    end

    def tsv(*args)
      TSV.open(stream, *args)
    end
  end
end
