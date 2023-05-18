require_relative 'transformer'
module TSV

  def self.attach(source, other, fields: nil, match_key: nil, other_key: nil, one2one: :fill, complete: false, insitu: true)
    source = TSV::Transformer.new source unless TSV === source || TSV::Parser === source
    other = TSV.open other unless TSV === other 

    match_key = (source.all_fields & other.all_fields).first if match_key.nil?
    match_key = source.key_field if match_key.nil? 
    other_key = match_key if other_key.nil?


    match_key = :key if match_key == source.key_field
    other_key = :key if other_key == other.key_field

    fields = [fields] if String === fields

    other.with_unnamed do
      source.with_unnamed do

        if other_key != :key || fields
          fields = other.all_fields - [other_key, source.key_field]
          other = other.reorder other_key, fields, one2one: one2one
        else
          fields = other.fields - [source.key_field, other_key]
        end

        source.fields = (source.fields + fields).uniq
        overlaps = source.identify_field(other.fields)

        empty_other_values = case source.type
                             when :list
                               [nil] * other.fields.length
                             when :flat
                               []
                             when :double
                               [[]] * other.fields.length
                             end

        match_key_pos = source.identify_field(match_key)
        source.each do |orig_key,current_values|
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
