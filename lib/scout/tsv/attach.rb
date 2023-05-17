module TSV

  def attach(other, match_key: nil, other_key: nil, fields: nil, one2one: :fill, complete: false)
    match_key = :key if match_key.nil?

    other_key = match_key if other_key.nil?

    other.with_unnamed do
      self.with_unnamed do

        if other_key != :key || fields
          fields = other.all_fields - [other_key, self.key_field]
          other = other.reorder other_key, fields, one2one: one2one
        else
          fields = other.fields - [self.key_field, other_key]
        end

        self.fields = (self.fields + fields).uniq
        overlaps = identify_field(other.fields)

        empty_other_values = case type
                             when :list
                               [nil] * other.fields.length
                             when :flat
                               []
                             when :double
                               [[]] * other.fields.length
                             end

        match_key_pos = identify_field(match_key)
        each do |orig_key,current_values|
          keys = (match_key == :key || match_key_pos == :key) ? [orig_key] : current_values[match_key_pos]
          keys = [keys] unless Array === keys

          keys.each do |current_key|
            other_values = other[current_key]

            if other_values.nil?
              other_values = empty_other_values
            elsif other.type == :flat
              other_values = [other_values]
            elsif other.type == :list && type == :double
              other_values = other_values.collect{|v| [v] }
            elsif other.type == :double && type == :list
              other_values = other_values.collect{|v| v.first }
            end

            other_values.zip(overlaps).each do |v,overlap|
              if type == :list
                current_values[overlap] = v if v[overlap].nil? || String === v[overlap] && v[overlap].empty?
              else
                current_values[overlap] ||= []
                current_values[overlap].concat (v - current_values[overlap])
              end
            end
          end
        end

        if complete && match_key == :key
          empty_self_values = case type
                              when :list
                                [nil] * self.fields.length
                              when :flat
                                []
                              when :double
                                [[]] * self.fields.length
                              end
          other.each do |other_key,other_values|
            next if self.include?(other_key)
            if other.type == :flat
              other_values = [other_values]
            elsif other.type == :list && type == :double
              other_values = other_values.collect{|v| [v] }
            elsif other.type == :double && type == :list
              other_values = other_values.collect{|v| v.first }
            end

            new_values = case type
                         when :list
                           [nil] * self.fields.length
                         when :flat
                           []
                         when :double
                           self.fields.length.times.collect{ [] }
                         end

            other_values.zip(overlaps).each do |v,overlap|
              if false && overlap == :key
                other_key = Array === v ? v : v.first
              elsif type == :list
                new_values[overlap] = v if v[overlap].nil? || String === v[overlap] && v[overlap].empty?
              else
                new_values[overlap].concat v
              end
            end
            self[other_key] = new_values
          end
        end
      end
    end

    self
  end
end
