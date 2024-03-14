module TSV
  class Transformer
    attr_accessor :unnamed, :parser, :dumper

    def initialize(parser, dumper = nil, unnamed: nil)
      if TSV::Parser === parser
        @parser = parser
      elsif TSV === parser
        @parser = parser
        @unnamed = parser.unnamed
      else
        @parser = TSV::Parser.new parser
      end
      @unnamed = unnamed unless unnamed.nil?
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
      return nil if fields.nil?
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
      kwargs[:bar] = "Transform #{Log.fingerprint @parser} into #{Log.fingerprint @target}" if TrueClass === kwargs[:bar]
      @dumper.init if @dumper.respond_to?(:init) && ! @dumper.initialized
      Log.debug "Transform #{Log.fingerprint @parser} into #{Log.fingerprint @dumper}"
      Open.traverse(@parser, *args, **kwargs) do |k,v|
        NamedArray.setup(v, @parser.fields, k) unless @unnamed || @parser.fields.nil?
        block.call k, v
      end
    end

    def each(*args, **kwargs, &block)
      kwargs[:into] = @dumper
      kwargs[:bar] = "Transform #{Log.fingerprint @parser} into #{Log.fingerprint @target}" if TrueClass === kwargs[:bar]
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
      @dumper.init if @dumper.respond_to?(:init) && ! @dumper.initialized
      @dumper.add key, value
    end

    def stream
      @dumper.stream
    end

    def tsv(*args)
      TSV === @dumper ? @dumper : TSV.open(@dumper, *args)
    end
  end

  def to_list
    res = self.annotate({})
    self.with_unnamed do
      transformer = Transformer.new self, res
      transformer.type = :list
      transformer.traverse do |k,v|
        case self.type
        when :single
          [k, [v]]
        when :double
          [k, v.collect{|v| v.first }]
        when :flat
          [k, v.slice(0,1)]
        end
      end
    end
    res
  end

  def to_double
    return self if self.type == :double
    res = self.annotate({})
    self.with_unnamed do
      transformer = Transformer.new self, res
      transformer.type = :double
      transformer.traverse do |k,v|
        case self.type
        when :single
          [k, [[v]]]
        when :list
          [k, v.collect{|v| [v] }]
        when :flat
          [k, [v]]
        end
      end
    end
    res
  end


  def to_single
    res = self.annotate({})
    transformer = Transformer.new self, res
    transformer.type = :single
    transformer.unnamed = true
    transformer.traverse do |k,v|
      v = v.first while Array === v
      [k, v]
    end
    res
  end

  def to_flat
    res = self.annotate({})
    transformer = Transformer.new self, res
    transformer.type = :flat
    transformer.traverse do |k,v|
      v = Array === v ? v.flatten : [v]
      [k, v]
    end
    res
  end
end

