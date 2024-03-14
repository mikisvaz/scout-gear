require_relative 'tsv'
require_relative 'association/fields'
require_relative 'association/util'

module Association
  def self.open(obj, source: nil, target: nil, fields: nil, **kwargs)
    all_fields = TSV.all_fields(obj)
    source_pos, field_pos, source_header, field_headers, source_format, target_format = headers(all_fields, fields, kwargs.merge(source: source, target: target))

    original_source_header = all_fields[source_pos]
    original_field_headers = all_fields.values_at(*field_pos)
    original_target_header = all_fields[field_pos.first]

    if source_format
      translation_files = [TSV.identifier_files(obj), Entity.identifier_files(source_format)]
      source_index = begin
                       TSV.translation_index(translation_files.flatten, source_header, source_format)
                     rescue
                       TSV.translation_index(translation_files.flatten, original_source_header, source_format)
                     end
    end

    if target_format
      translation_files = [TSV.identifier_files(obj), Entity.identifier_files(target_format)]
      target_index = begin
                       TSV.translation_index(translation_files.flatten, field_headers.first, target_format)
                     rescue
                       TSV.translation_index(translation_files.flatten, original_target_header, target_format)
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
                        original_source_header
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
        res = obj.reorder original_source_header, all_fields.values_at(*field_pos)
      else
        res = TSV.open(obj, key_field: original_source_header, fields: all_fields.values_at(*field_pos))
      end
      res.key_field = final_key_field
      res.fields = final_fields

      return res
    end

    transformer = TSV::Transformer.new obj
    transformer.key_field = final_key_field
    transformer.fields = final_fields

    transformer.traverse key_field: original_source_header, fields: all_fields.values_at(*field_pos) do |k,v|
      k = source_index[k] if source_index
      v[0] = Array === v[0] ? target_index.values_at(*v[0]) : target_index[v[0]] if target_index
      [k, v]
    end

    transformer
  end

  def self.database(*args, **kwargs)
    tsv = open(*args, **kwargs)
    TSV::Transformer === tsv ? tsv.tsv : tsv
  end
end