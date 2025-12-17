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

  def unzip_replicates
    raise "Can only unzip replicates in :double TSVs" unless type == :double

    new = {}
    self.with_unnamed do
      through do |k,vs|
        NamedArray.zip_fields(vs).each_with_index do |v,i|
          new[k + "(#{i})"] = v
        end
      end
    end

    self.annotate(new)
    new.type = :list

    new
  end

  def zip(merge = false, field = "New Field", sep = ":")
    new = {}
    self.annotate new

    new.type = :double if merge

    new.with_unnamed do
      if merge
        self.through do |key,values|
          new_key, new_value = key.split(sep)
          new_values = values + [[new_value] * values.first.length]
          if new.include? new_key
            current = new[new_key]
            current.each_with_index do |v,i|
              v.concat(new_values[i])
            end
          else
            new[new_key] = new_values
          end
        end
      else
        self.through do |key,values|
          new_key, new_value = key.split(sep)
          new_values = values + [new_value]
          new[new_key] = new_values
        end
      end
    end

    if self.key_field and self.fields
      new.key_field = self.key_field.partition(sep).first
      new.fields = new.fields + [field]
    end

    new
  end

end
