module TSV
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
    when (String === method || Symbol === method)
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
      when (Array === method and (key == :key or key_field == key))
        with_unnamed do
          keys.each do |key|
            new[key] = self[key] if invert ^ (method.include? key)
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

      when (String === method and method =~ /name:(.*)/)
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

  def reorder(key_field = nil, fields = nil, merge: true, one2one: true) 
    res = self.annotate({})
    key_field_name, field_names = traverse key_field, fields, one2one: one2one do |k,v|
      if @type == :double && merge && res.include?(k)
        current = res[k]
        if merge == :concat
          v.each_with_index do |new,i|
            next if new.empty?
            current[i].concat(new)
          end
        else
          merged = []
          v.each_with_index do |new,i|
            next if new.empty?
            merged[i] = current[i] + new
          end
          res[k] = merged
        end
      else
        res[k] = v
      end
    end
    res.key_field = key_field_name
    res.fields = field_names
    res
  end

  def slice(fields)
    reorder :key, fields
  end
end
