require 'matrix'

module TSV
  def reorder(key_field = nil, fields = nil, merge: true, one2one: true, **kwargs) 
    res = self.annotate({})
    res.type = kwargs[:type] if kwargs.include?(:type)
    kwargs[:one2one] = one2one
    key_field_name, field_names = with_unnamed do
      traverse key_field, fields, **kwargs do |k,v|
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
        elsif @type == :flat
          res[k] ||= []
          if merge == :concat
            res[k].concat v
          else
            res[k] += v
          end
        else
          res[k] = v
        end
      end
    end

    res.key_field = key_field_name
    res.fields = field_names
    res
  end

  def slice(fields, **kwargs)
    reorder :key, fields, **kwargs
  end

  def column(field, **kwargs)
    new_type = case type
               when :double, :flat
                 :flat
               else
                 :single
               end

    kwargs[:type] = new_type
    slice(field, **kwargs)
  end

  def transpose_list(key_field="Unkown ID")
    new_fields = keys.dup
    new = self.annotate({})
    TSV.setup(new, :key_field => key_field, :fields => new_fields, :type => type, :filename => filename, :identifiers => identifiers)

    m = Matrix.rows values 
    new_rows = m.transpose.to_a

    fields.zip(new_rows) do |key,row|
      new[key] = row
    end

    new
  end

  def transpose_double(key_field = "Unkown ID")
    sep = "-!SEP--#{rand 10000}!-"
    tmp = self.to_list{|v| v * sep}
    new = tmp.transpose_list(key_field)
    new.to_double{|v| v.split(sep)}
  end

  def transpose(key_field = "Unkown ID")
    case type
    when :single, :flat
      self.to_list.transpose_list key_field
    when :list
      transpose_list key_field
    when :double
      transpose_double key_field
    end
  end
end
