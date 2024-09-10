module TSV
  def self.select(key, values, method, fields: nil, field: nil, invert: false, type: nil, sep: nil, &block)
    return ! select(key, values, method, field: field, invert: false, type: type, sep: sep, &block) if invert

    return yield(key, values) if method.nil? && block_given

    if Hash === method
      if method.include?(:invert)
        method = method.dup
        invert = method.delete(:invert)
        return select(key, values, method, fields: fields, field: field, invert: invert, type: type, sep: sep, &block)
      end
      field = method.keys.first
      value = method[field]
      return select(key, values, value, fields: fields, field: field, invert: invert, type: type, sep: sep, &block)
    end

    if field
      field = NamedArray.identify_name(fields, field) if fields && String === field
      set = field == :key ? [key] : (type == :double ? values[field].split(sep) : values[field])
    else
      set = [key, (type == :double ? values.collect{|v| v.split(sep) } : values)]
    end

    if Array === set
      set.flatten!
    else
      set = [set]
    end

    case method
    when Array
      (method & set).any?
    when Regexp
      set.select{|v| v =~ method }.any?
    when Symbol
      set.first.send(method)
    when Numeric
      set.size > method
    when String
      if block_given?
        field = method
        field = fields.index?(field) if fields && String === field
        case 
        when block.arity == 1
          if (method == key_field or method == :key)
            yield(key)
          else
            yield(values[method])
          end
        when block.arity == 2
          if (method == key_field or method == :key)
            yield(key, key)
          else
            yield(key, values[method])
          end
        end
      elsif m = method.match(/^([<>]=?)(.*)/)
        set.select{|v| v.to_f.send($1, $2.to_f) }.any?
      else
        set.select{|v| v == method }.any?
      end
    when Proc
      set.select{|v| method.call(v) }.any?
    end
  end

  def select(method = nil, invert = false, &block)
    new = TSV.setup({}, :key_field => key_field, :fields => fields, :type => type, :filename => filename, :identifiers => identifiers)

    self.annotate(new)
    
    case
    when (method.nil? and block_given?)
      through do |key, values|
        new[key] = values if invert ^ (yield key, values)
      end
    when Array === method
      method = Set.new method
      with_unnamed do
        case type
        when :single
          through do |key, value|
            new[key] = value if invert ^ (method.include? key or method.include? value)
          end
        when :list, :flat
          through do |key, values|
            new[key] = values if invert ^ (method.include? key or (method & values).length > 0)
          end
        else
          through do |key, values|
            new[key] = values if invert ^ (method.include? key or (method & values.flatten).length > 0)
          end
        end
      end
    when Regexp === method
      with_unnamed do
        through do |key, values|
          new[key] = values if invert ^ ([key,values].flatten.select{|v| v =~ method}.any?)
        end
      end
    when ((String === method) || (Symbol === method))
      if block_given?
        case 
        when block.arity == 1
          with_unnamed do
            case
            when (method == key_field or method == :key)
              through do |key, values|
                new[key] = values if invert ^ (yield(key))
              end
            when (type == :single or type == :flat)
              through do |key, value|
                new[key] = value if invert ^ (yield(value))
              end
            else
              pos = identify_field method
              raise "Field #{ method } not identified. Available: #{ fields * ", " }" if pos.nil?

              through do |key, values|
                new[key] = values if invert ^ (yield(values[pos]))
              end
            end
          end
        when block.arity == 2
          with_unnamed do
            case
            when (method == key_field or method == :key)
              through do |key, values|
                new[key] = values if invert ^ (yield(key, key))
              end
            when (type == :single or type == :flat)
              through do |key, value|
                new[key] = value if invert ^ (yield(key, value))
              end
            else
              pos = identify_field method
              through do |key, values|
                new[key] = values if invert ^ (yield(key, values[pos]))
              end
            end

          end
        end

      else
        with_unnamed do
          through do |key, values|
            new[key] = values if invert ^ ([key,values].flatten.select{|v| v == method}.any?)
          end
        end
      end
    when Hash === method
      key  = method.keys.first
      method = method.values.first
      case
      when ((Array === method) and (key == :key or key_field == key))
        with_unnamed do
          if invert
            keys.each do |key|
              new[key] = self[key] unless method.include?(key)
            end
          else
            method.each do |key|
              new[key] = self[key] if self.include?(key)
            end
          end
        end
      when Array === method
        with_unnamed do
          method = Set.new method unless Set === method
          case type
          when :single
            through :key, key do |key, value|
              new[key] = self[key] if invert ^ (method.include? value)
            end
          when :list
            through :key, key do |key, values|
              new[key] = self[key] if invert ^ (method.include? values.first)
            end
          when :flat #untested
            through :key, key do |key, values|
              new[key] = self[key] if invert ^ ((method & values.flatten).any?)
            end
          else
            through :key, key do |key, values|
              new[key] = self[key] if invert ^ ((method & values.flatten).any?)
            end
          end
        end

      when Regexp === method
        with_unnamed do
          through :key, key do |key, values|
            values = [values] if type == :single
            new[key] = self[key] if invert ^ (values.flatten.select{|v| v =~ method}.any?)
          end
        end

      when ((String === method) and (method =~ /name:(.*)/))
        name = $1
        old_unnamed = self.unnamed
        self.unnamed = false
        if name.strip =~ /^\/(.*)\/$/
          regexp = Regexp.new $1
          through :key, key do |key, values|
            case type
            when :single
              values = values.annotate([values])
            when :double
              values = values[0]
            end
            new[key] = self[key] if invert ^ (values.select{|v| v.name =~ regexp}.any?)
          end
        else
          through :key, key do |key, values|
            case type
            when :single
              values = values.annotate([values])
            when :double
              values = values[0]
            end
            new[key] = self[key] if invert ^ (values.select{|v| v.name == name}.any?)
          end
        end
        self.unnamed = old_unnamed

      when String === method
        if method =~ /^([<>]=?)(.*)/
          with_unnamed do
            through :key, key do |key, values|
              value = Array === values ? values.flatten.first : values
              new[key] = self[key] if value.to_f.send($1, $2.to_f)
            end
          end
        else
          with_unnamed do
            through :key, key do |key, values|
              values = [values] if type == :single
              new[key] = self[key] if invert ^ (values.flatten.select{|v| v == method}.length > 0)
            end
          end
        end
      when Numeric === method
        with_unnamed do
          through :key, key do |key, values|
            new[key] = self[key] if invert ^ (values.flatten.length >= method)
          end
        end
      when Proc === method
        with_unnamed do
          through :key, key do |key, values|
            values = [values] if type == :single
            new[key] = self[key] if invert ^ (values.flatten.select{|v| method.call(v)}.length > 0)
          end
        end
      end
    end
    new
  end

  def subset(keys)
    new = self.annotate({})
    self.with_unnamed do
      keys.each do |k|
        new[k] = self[k] if self.include?(k)
      end
    end
    new
  end

  def chunked_values_at(keys, max = 5000)
    Misc.ordered_divide(keys, max).inject([]) do |acc,c|
      new = self.values_at(*c)
      new.annotate acc if new.respond_to? :annotate and acc.empty?
      acc.concat(new)
    end
  end
end
