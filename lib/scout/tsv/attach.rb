module TSV

  def self.match_keys(source, other, match_key: nil, other_key: nil)
    match_key = (source.all_fields & other.all_fields).first if match_key.nil?

    if match_key.nil?
      source.all_fields.collect do |f|
        other_key = other.identify_field(f)
        if other_key
          other_key = other.key_field if other_key == :key
          match_key = f
          break
        end
      end
    end

    if match_key.nil?
      other.all_fields.collect do |f|
        match_key = source.identify_field(f)
        if match_key
          other_key = f
          break
        end
      end
    end

    match_key = source.key_field if match_key.nil? 

    if other_key.nil?
      other_key = other.identify_field(match_key)
    end

    other_key = other.key_field if other_key.nil?

    match_key = :key if match_key == source.key_field
    other_key = :key if other_key == other.key_field

    [match_key, other_key]
  end

  def self.attach(source, other, target: nil, fields: nil, match_key: nil, other_key: nil, one2one: true, complete: false, insitu: nil, persist_input: false, bar: nil)
    source = TSV::Transformer.new source unless TSV === source || TSV::Parser === source
    other = TSV.open other, persist: persist_input unless TSV === other 

    fields = [fields] if String === fields

    match_key, other_key = TSV.match_keys(source, other, match_key: match_key, other_key: other_key)

    if TSV::Transformer === source
      source.dumper = case target
                      when :stream
                        TSV::Dumper.new(source.options.merge(sep: "\t"))
                      when nil
                        TSV.setup({}, **source.options.dup)
                      else
                        target
                      end
    end

    other.with_unnamed do
      source.with_unnamed do

        other_key_name = other_key == :key ? other.key_field : other_key
        other_key_name = other.fields[other_key_name] if Integer === other_key
        fields = other.all_fields - [other_key_name, source.key_field] if fields.nil?

        if other_key != :key 
          other = other.reorder other_key, fields, one2one: one2one
        end

        other_field_positions = other.identify_field(fields) 

        log_message = "Attach #{Log.fingerprint fields - source.fields} to #{Log.fingerprint source} (#{[match_key, other_key] * "=~"})"
        Log.debug log_message
        bar = log_message if TrueClass === bar

        new = fields - source.fields

        source.fields = (source.fields + fields).uniq

        overlaps = source.identify_field(fields)

        empty_other_values = case source.type
                             when :list
                               [nil] * other.fields.length
                             when :flat
                               []
                             when :double
                               [[]] * other.fields.length
                             end

        insitu = TSV === source ? true : false if insitu.nil?

        match_key_pos = source.identify_field(match_key)
        source.traverse bar: bar, unnamed: true do |orig_key,current_values|
          keys = (match_key == :key || match_key_pos == :key) ? [orig_key] : current_values[match_key_pos]
          keys = [keys] unless Array === keys

          current_values = current_values.dup unless insitu
          keys.each do |current_key|
            other_values = other[current_key]

            if other_values.nil?
              other_values = empty_other_values
            elsif other.type == :flat
              other_values = [other_values]
            elsif other.type == :list && source.type == :double
              other_values = other_values.collect{|v| [v] }
            elsif other.type == :double && source.type == :list
              other_values = other_values.collect{|v| v.first }
            end

            other_values = other_values.values_at *other_field_positions

            other_values.zip(overlaps).each do |v,overlap|
              if source.type == :list
                current_values[overlap] = v if current_values[overlap].nil? || String === current_values[overlap] && current_values[overlap].empty?
              else
                current_values[overlap] ||= []
                current_values[overlap].concat (v - current_values[overlap])
              end
            end
          end
          source[orig_key] = current_values unless insitu
          nil
        end

        if complete && match_key == :key
          empty_self_values = case source.type
                              when :list
                                [nil] * source.fields.length
                              when :flat
                                []
                              when :double
                                [[]] * source.fields.length
                              end
          other.each do |other_key,other_values|
            next if source.include?(other_key)
            if other.type == :flat
              other_values = [other_values]
            elsif other.type == :list && source.type == :double
              other_values = other_values.collect{|v| [v] }
            elsif other.type == :double && source.type == :list
              other_values = other_values.collect{|v| v.first }
            end

            new_values = case source.type
                         when :list
                           [nil] * source.fields.length
                         when :flat
                           []
                         when :double
                           source.fields.length.times.collect{ [] }
                         end

            other_values.zip(overlaps).each do |v,overlap|
              if false && overlap == :key
                other_key = Array === v ? v : v.first
              elsif source.type == :list
                new_values[overlap] = v if v[overlap].nil? || String === v[overlap] && v[overlap].empty?
              else
                new_values[overlap].concat v
              end
            end
            source[other_key] = new_values
          end
        end
      end
    end

    source
  end

  def attach(*args, **kwargs)
    TSV.attach(self, *args, **kwargs)
  end
end
