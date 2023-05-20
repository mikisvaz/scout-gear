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
        @dumper = TSV::Dumper.new(@parser)
        @dumper.sep = "\t"
      else
        @dumper = dumper
      end
    end

    def key_field=(key_field)
      @dumper.key_field = key_field
    end

    def fields=(fields)
      @dumper.fields = fields
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
      @dumper.key_field
    end

    def fields
      @dumper.fields
    end

    def all_fields
      [key_field] + fields
    end

    def options
      @dumper.options
    end

    def identify_field(name)
      TSV.identify_field key_field, fields, name
    end

    def traverse(*args, **kwargs, &block)
      kwargs[:into] = @dumper
      @dumper.init if @dumper.respond_to?(:init) && ! @dumper.initialized
      Log.debug "Transform #{Log.fingerprint @parser} into #{Log.fingerprint @dumper}"
      Open.traverse(@parser, *args, **kwargs) do |k,v|
        NamedArray.setup(v, @parser.fields, k) unless @unnamed
        block.call k, v
      end
    end

    def each(*args, **kwargs, &block)
      kwargs[:into] = @dumper
      @dumper.init if @dumper.respond_to?(:init) && ! @dumper.initialized
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
      TSV === @dumper ? @dumper : TSV.open(stream, *args)
    end
  end

  def to_list
    transformer = Transformer.new self
    transformer.type = :list
    transformer.traverse do |k,v|
      [k, v.collect{|v| v.first }]
    end
    transformer.tsv
  end
end

