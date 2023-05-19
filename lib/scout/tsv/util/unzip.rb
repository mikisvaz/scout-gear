module TSV

  def self.unzip(source, field, sep: ":", delete: true, stream: false, type: :list, merge: false)
    transformer = TSV::Transformer.new source, unnamed: true

    field_pos = transformer.identify_field(field)
    new_fields = transformer.fields.dup
    field_name = new_fields[field_pos]
    new_fields.delete_at(field_pos) if delete
    new_key_field = [transformer.key_field, field_name] * sep

    type = :double if merge

    transformer.fields = new_fields
    transformer.key_field = new_key_field
    transformer.type = type

    transformer.traverse unnamed: true do |k,v|
      if source.type == :double
        res = NamedArray.zip_fields(v).collect do |_v|
          field_value = _v[field_pos]

          if delete
            new_values = _v.dup
            new_values.delete_at field_pos
          else
            new_values = _v
          end

          new_key = [k,field_value] * sep
          new_values = new_values.collect{|e| [e] } if transformer.type == :double
          [new_key, new_values]
        end
        
        MultipleResult.setup(res)
      else
        field_value = v[field_pos]

        if delete
          new_values = v.dup
          new_values.delete_at field_pos
        else
          new_values = v
        end

        new_key = [k,field_value] * sep

        new_values = new_values.collect{|e| [e] } if transformer.type == :double

        [new_key, new_values]
      end
    end

    stream ? transformer : transformer.tsv(merge: merge)
  end

  def unzip(*args, **kwargs)
    TSV.unzip(self, *args, **kwargs)
  end
end
