require_relative 'tsv'
require_relative 'association/fields'
require_relative 'association/util'
require_relative 'association/index'
require_relative 'association/item'

module Association
  def self.open(obj, source: nil, target: nil, fields: nil, source_format: nil, target_format: nil, **kwargs)
    all_fields = TSV.all_fields(obj)
    source_pos, field_pos, source_header, field_headers, source_format, target_format = headers(all_fields, fields, kwargs.merge(source: source, target: target, source_format: source_format, target_format: target_format))

    original_source_header = all_fields[source_pos]
    original_field_headers = all_fields.values_at(*field_pos)
    original_target_header = all_fields[field_pos.first]

    type, identifiers = IndiferentHash.process_options kwargs, :type, :identifiers

    if source_format
      translation_files = [TSV.identifier_files(obj), Entity.identifier_files(source_format), identifiers].flatten.compact
      source_index = begin
                       TSV.translation_index(translation_files, source_header, source_format)
                     rescue
                       TSV.translation_index(translation_files, original_source_header, source_format)
                     end
    end

    if target_format
      translation_files = [TSV.identifier_files(obj), Entity.identifier_files(target_format), identifiers].flatten.compact
      target_index = begin
                       TSV.translation_index(translation_files, field_headers.first, target_format)
                     rescue
                       TSV.translation_index(translation_files, original_target_header, target_format)
                     end
    end

    final_key_field = if source_format
                        if m = original_source_header.match(/(.*) \(.*\)/)
                          m[1] + " (#{source_format})"
                        elsif m = source_header.match(/(.*) \(.*\)/)
                          m[1] + " (#{source_format})"
                        else
                          source_format
                        end
                      else
                        source_header || original_source_header
                      end

    final_fields = if target_format
                     fields = original_field_headers
                     if m = original_target_header.match(/(.*) \(.*\)/)
                       fields[0] = m[1] + " (#{target_format})"
                     elsif m = field_headers.first.match(/(.*) \(.*\)/)
                       fields[0] = m[1] + " (#{target_format})"
                     else
                       fields[0] = target_format
                     end
                     fields
                   else
                     original_field_headers
                   end


    if source_index.nil? && target_index.nil?
      if TSV === obj
        IndiferentHash.pull_keys kwargs, :persist
        type = kwargs[:type] || obj.type
        res = obj.reorder original_source_header, all_fields.values_at(*field_pos), **kwargs.merge(type: type, merge: true)
      else
        res = TSV.open(obj, key_field: original_source_header, fields: all_fields.values_at(*field_pos), **kwargs.merge(type: type))
      end
      res.key_field = final_key_field
      res.fields = final_fields

      return res
    end

    transformer = TSV::Transformer.new obj
    transformer.key_field = final_key_field
    transformer.fields = final_fields
    transformer.type = type if type

    transformer.traverse key_field: original_source_header, fields: all_fields.values_at(*field_pos) do |k,v|
      v = v.dup if TSV === obj
      k = source_index[k] if source_index
      v[0] = Array === v[0] ? target_index.values_at(*v[0]) : target_index[v[0]] if target_index
      [k, v]
    end

    transformer
  end

  def self.database(*args, **kwargs)
    tsv = open(*args, **kwargs)
    TSV::Transformer === tsv ? tsv.tsv(merge: true) : tsv
  end
end
