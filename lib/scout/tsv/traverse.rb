require_relative 'parser'
module TSV
  def traverse(key_field_pos = :key, fields_pos = nil, type: nil, one2one: false, unnamed: nil, key_field: nil, fields: nil, bar: false, cast: nil, select: nil, uniq: false, &block)
    key_field = key_field_pos if key_field.nil?
    fields = fields_pos.dup if fields.nil?
    type = @type if type.nil?
    key_pos = self.identify_field(key_field)
    fields = self.all_fields if fields == :all
    fields = [fields] unless fields.nil? || Array === fields
    positions = (fields.nil? || fields == :all) ? nil : self.identify_field(fields)
    positions = nil if fields == self.fields
    unnamed = @unnamed if unnamed.nil?
    unnamed = false if unnamed.nil?

    if key_pos == :key
      key_name = @key_field
    else
      key_name = @fields[key_pos]
      if positions.nil?
        positions = (0..@fields.length-1).to_a
        positions.delete_at key_pos
        positions.unshift :key
      end
    end

    fields = positions.collect{|p| p == :key ? self.key_field : self.fields[p] } if positions

    if positions.nil? && key_pos == :key
      field_names = @fields.dup
    elsif positions.nil? && key_pos != :key
      field_names = @fields.dup
      field_names.delete_at key_pos unless fields == :all
    elsif positions.include?(:key)
      field_names = positions.collect{|p| p == :key ? @key_field : @fields[p] }
    else
      field_names = @fields.values_at *positions
    end

    key_index = positions.index :key if positions
    positions.delete :key if positions

    log_message = "Traverse #{Log.fingerprint self}"
    Log.debug log_message
    bar = log_message if TrueClass === bar

    invert = select.delete :invert if Hash === select
    type_swap_tag = [type.to_s, @type.to_s] * "_"
    Log::ProgressBar.with_obj_bar(self, bar) do |bar|
      with_unnamed unnamed do
        each do |key,values|
          next unless TSV.select key, values, select, invert: invert if select
          bar.tick if bar
          values = [values] if @type == :single
          if positions.nil?
            if key_pos != :key
              values = values.dup
              if @type == :flat
                key = values
              else
                key = values.delete_at(key_pos)
              end
            end
          else 
            orig_key = key
            key = @type == :flat ? values : values[key_pos] if key_pos != :key 

            values = values.values_at(*positions)
            if key_index
              if @type == :double
                values.insert key_index, [orig_key]
              else
                values.insert key_index, orig_key
              end
            end
          end

          if ! unnamed && fields
            case @type
            when :flat, :single
              values = Entity.prepare_entity(values, fields.first)
            else
              values = NamedArray.setup(values, fields, entity_options)
            end
          end

          values = TSV.cast_value(values, cast) if cast

          if Array === key 
            key = key.uniq if uniq
            if @type == :double && one2one
              if one2one == :strict
                key.each_with_index do |key_i,i|
                  if type == :double
                    v_i = values.collect{|v| [v[i]] }
                  else
                    v_i = values.collect{|v| v[i] }
                  end
                  yield key_i, v_i
                end
              else
                key.each_with_index do |key_i,i|
                  if type == :double
                    v_i = values.collect{|v| [v[i] || v.first] }
                  else
                    v_i = values.collect{|v| v[i] || v.first }
                  end
                  yield key_i, v_i, @fields
                end
              end
            else
              key.each_with_index do |key_i, i|
                if type == :double
                  yield key_i, values
                elsif type == :list
                  yield key_i, values.collect{|v| v[i] }
                elsif type == :flat
                  yield key_i, values.flatten
                elsif type == :single
                  yield key_i, values.first
                end
              end
            end
          else
            if type == @type
              if type == :single
                yield key, values.first
              else
                yield key, values
              end
            else
              case type_swap_tag
              when "double_list"
                yield key, values.collect{|v| [v] }
              when "double_flat"
                yield key, [values]
              when "double_single"
                yield key, [values]
              when "list_double"
                yield key, values.collect{|v| v.first }
              when "list_flat"
                yield key, [values.first]
              when "list_single"
                yield key, values
              when "flat_double"
                yield key, values.flatten
              when "flat_list"
                yield key, values.flatten
              when "flat_single"
                yield key, values
              when "single_double"
                yield key, values.flatten.first
              when "single_list"
                yield key, values.first
              when "single_flat"
                yield key, values.first
              end
            end
          end
        end
      end
    end
    

    [key_name, field_names]
  end

  alias through traverse
end
