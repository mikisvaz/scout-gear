require_relative 'annotation/repo'
module Annotation

  def self.obj_tsv_values(obj, fields)

    annotation_info = obj.annotation_info
    annotation_info[:annotated_array] = true if AnnotatedArray === obj

    fields.collect do |field|
      field = field.to_s if Symbol === field
      case field
      when Proc
        field.call(obj)

      when "JSON"
        annotation_info.to_json

      when "annotation_types"
        annotation_info[:annotation_types].collect{|t| t.to_s} * "|"

      when "annotated_array"
        AnnotatedArray === obj

      when "literal"
        (Array === obj ? "Array:" << obj * "|" : obj).gsub(/\n|\t/, ' ')

      else
        if annotation_info.include?(field.to_sym)
          res = annotation_info[field.to_sym]
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

    annotations = if Annotation.is_annotated?(objs)
                    objs.annotation_hash.keys
                  elsif (Array === objs && objs.any?)
                    first = objs.compact.first
                    if Annotation.is_annotated?(first)
                      objs.compact.first.annotation_hash.keys
                    else
                      raise "Objects didn't have annotations"
                    end
                  else
                    []
                  end

    if fields.empty?
      fields = annotations + [:annotation_types]
    elsif fields == ["all"] || fields == [:all]
      fields = annotations + [:annotation_types, :literal]
    end

    fields = fields.collect{|f| Symbol === f ? f.to_s : f }

    tsv = TSV.setup({}, :key_field => nil, :fields => fields, :type => :list, :unnamed => true)

    case
    when Annotation.is_annotated?(objs)
      tsv.key_field = "List"

      tsv[objs.id] = self.list_tsv_values(objs, fields).dup
    when Array === objs 
      tsv.key_field = "ID"

      if Annotation.is_annotated?(objs.compact.first)
        objs.compact.each_with_index do |obj,i|
          tsv[obj.id + "#" << i.to_s] = self.obj_tsv_values(obj, fields).dup
        end
      elsif (objs.any? && Annotation.is_annotated?(objs.compact.first.compact.first))
        objs.flatten.compact.each_with_index do |obj,i|
          tsv[obj.id + "#" << i.to_s] = self.obj_tsv_values(obj, fields).dup
        end
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

    self.setup(object, info[:annotation_types], info)

    object.extend AnnotatedArray if Array === object

    object
  end

  def self.load_tsv(tsv)
    tsv.with_unnamed do
      annotated_objects = tsv.collect do |id, values|
        Annotation.load_tsv_values(id, values, tsv.fields)
      end

      case tsv.key_field
      when "List"
        annotated_objects.first
      else
        annotated_objects
      end
    end
  end
end
