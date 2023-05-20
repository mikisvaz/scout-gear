module TSV

  def self.unzip(source, field, target: nil, sep: ":", delete: true, type: :list, merge: false, one2one: true, bar: nil)
    source = TSV::Parser.new source if String === source

    field_pos = source.identify_field(field)
    new_fields = source.fields.dup
    field_name = new_fields[field_pos]
    new_fields.delete_at(field_pos) if delete
    new_key_field = [source.key_field, field_name] * sep
    type = :double if merge

    stream = target == :stream

    target = case target
             when :stream
               TSV::Dumper.new(source.options.merge(sep: "\t"))
             when nil
               TSV.setup({})
             else
               target
             end
               
    target.fields = new_fields
    target.key_field = new_key_field
    target.type = type

    transformer = TSV::Transformer.new source, target, unnamed: true

    bar = "Unzip #{new_key_field}" if TrueClass === bar

    transformer.traverse unnamed: true, one2one: one2one, bar: bar do |k,v|
      if source.type == :double
        if one2one
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
        else
          all_values = v.collect{|e| e.dup }
          all_values.delete_at field_pos if delete
          res = NamedArray.zip_fields(v).collect do |_v|
            field_value = _v[field_pos]

            new_key = [k,field_value] * sep
            new_values = all_values if transformer.type == :double
            [new_key, new_values]
          end
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
