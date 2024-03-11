module MetaExtension

  def self.obj_tsv_values(obj, fields)

    extension_info = obj.extension_info
    extension_info[:extended_array] = true if ExtendedArray === obj

    fields.collect do |field|
      field = field.to_s if Symbol === field
      case field
      when Proc
        field.call(obj)

      when "JSON"
        extension_info.to_json

      when "extension_types"
        extension_info[:extension_types].collect{|t| t.to_s} * "|"

      when "extended_array"
        ExtendedArray === obj

      when "literal"
        (Array === obj ? "Array:" << obj * "|" : obj).gsub(/\n|\t/, ' ')

      else
        if extension_info.include?(field.to_sym)
          res = extension_info[field.to_sym]
          Array === res ? "Array:" << res * "|" : res
        elsif self.respond_to?(field)
          res = self.send(field)
          Array === res ? "Array:"<< res * "|" : res
        else
          raise
        end
      end
    end
  end

  def self.list_tsv_values(objs, fields)
    obj_tsv_values(objs, fields)
  end
  

  def self.tsv(objs, *fields)
    return nil if objs.nil?

    fields = fields.flatten.compact.uniq

    extension_attrs = if MetaExtension.is_extended?(objs) 
                        objs.extension_attrs 
                      elsif (Array === objs && objs.any?)
                        objs.compact.first.extension_attrs
                      else
                        nil
                      end

    if fields.empty?
      fields = extension_attrs + [:extension_types]
    elsif fields == ["all"] || fields == [:all]
      fields = extension_attrs + [:extension_types, :literal]
    end

    fields = fields.collect{|f| Symbol === f ? f.to_s : f }

    tsv = TSV.setup({}, :key_field => nil, :fields => fields, :type => :list, :unnamed => true)

    case
    when MetaExtension.is_extended?(objs)
      tsv.key_field = "List"

      tsv[objs.extended_digest] = self.list_tsv_values(objs, fields).dup
    when Array === objs 
      tsv.key_field = "ID"

      objs.compact.each_with_index do |obj,i|
        tsv[obj.extended_digest + "#" << i.to_s] = self.obj_tsv_values(obj, fields).dup
      end
    else
      raise "Annotations need to be an Array to create TSV"
    end

    tsv
  end

  # Load TSV

  def self.resolve_tsv_array(entry)
    if String === entry && entry =~ /^Array:/
      entry["Array:".length..-1].split("|")
    else
      entry
    end
  end

  def self.load_info(fields, values)
    info = {}
    fields.each_with_index do |field,i|
      next if field == "literal"

      case field
      when "JSON"
        JSON.parse(values[i]).each do |key, value|
          info[key.to_sym] = value
        end
      when nil
        next
      else
        info[field.to_sym] = resolve_tsv_array(values[i])
      end
    end
    info
  end

  def self.load_tsv_values(id, values, *fields)
    fields = fields.flatten
    literal_pos = fields.index "literal"

    object = case
             when literal_pos
               values[literal_pos].tap{|o| o.force_encoding(Encoding.default_external)}
             else
               id.dup
             end

    object = resolve_tsv_array(object)

    if Array === values.first
      NamedArray.zip_fields(values).collect do |v|
        info = load_info(fields, v)
      end
    else
      info = load_info(fields, values)
    end

    self.setup(object, info[:extension_types], info)

    object
  end

  def self.load_tsv(tsv)
    tsv.with_unnamed do
      extended_objects = tsv.collect do |id, values|
        MetaExtension.load_tsv_values(id, values, tsv.fields)
      end

      case tsv.key_field 
      when "List"
        extended_objects.first
      else
        extended_objects
      end
    end
  end
end
