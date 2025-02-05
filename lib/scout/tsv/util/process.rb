module TSV
  def process(field, &block)
    field_pos = identify_field field

    through do |key, values|
      case
      when type == :single
        field_values = values
      when type == :flat
        field_values = values
      else
        next if values.nil?
        field_values = values[field_pos]
      end

      new_values = case 
                   when block.arity == 1
                     yield(field_values)
                   when block.arity == 2
                     yield(field_values, key)
                   when block.arity == 3
                     yield(field_values, key, values)
                   else
                     raise "Unexpected arity in block, must be 1, 2 or 3: #{block.arity}"
                   end

      case
      when type == :single
        self[key] = new_values
      when type == :flat
        self[key] = new_values
      else
        if ! values[field_pos].frozen? && ! NamedArray === values && ((String === values[field_pos] && String === new_values) ||
          (Array === values[field_pos] && Array === new_values))
          values[field_pos].replace new_values
        else
          values[field_pos] = new_values
        end
        self[key] = values
      end
    end

    self
  end

  def add_field(name = nil)
    keys.each do |key|
      values = self[key]
      new_values = yield(key, values)
      new_values = [new_values].compact if type == :double and not Array === new_values

      case
      when type == :single
        values = new_values
      when (values.nil? and (fields.nil? or fields.empty?))
        values = [new_values]
      when values.nil?  
        values = [nil] * fields.length + [new_values]
      when Array === values
        values += [new_values]
      else
        values << new_values
      end

      self[key] = values
    end

    if not fields.nil? and not name.nil?
      new_fields = self.fields + [name]
      self.fields = new_fields
    end

    self
  end

  def remove_duplicates(pivot = 0)
    new = self.annotate({})
    self.through do |k,values|
      new[k] = NamedArray.zip_fields(NamedArray.zip_fields(values).uniq)
    end
    new
  end
end
