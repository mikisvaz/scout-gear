require_relative 'tsv'
require_relative 'association/fields'
require_relative 'association/util'
require_relative 'association/index'
require_relative 'association/item'

module Association
  def self.open(obj, source: nil, target: nil, fields: nil, source_format: nil, target_format: nil, format: nil, **kwargs)
    IndiferentHash.setup(kwargs)
    source = kwargs.delete :source if kwargs.include?(:source)
    target = kwargs.delete :target if kwargs.include?(:target)

    if Path.is_filename?(obj)
      tsv_header_options = TSV.parse_options(obj)
      tsv_header_options = tsv_header_options.slice(TSV.acceptable_parser_options)
      options = tsv_header_options.merge(kwargs)
    else
      options = kwargs.dup
    end

    if String === obj && options[:namespace] && obj.include?("NAMESPACE")
      new_obj = obj.gsub(/\[?NAMESPACE\]?/, options[:namespace])
      obj.annotate(new_obj)
      obj = new_obj
    end

    all_fields = TSV.all_fields(obj)
    source_pos, field_pos, source_header, field_headers, source_format, target_format = headers(all_fields, fields, options.merge(source: source, target: target, source_format: source_format, target_format: target_format, format: format))

    original_source_header = all_fields[source_pos]
    original_field_headers = all_fields.values_at(*field_pos)
    original_target_header = all_fields[field_pos.first]

    type, identifiers = IndiferentHash.process_options options, :type, :identifiers

    if source_format || target_format
      translation_files = [TSV.identifier_files(obj), Entity.identifier_files(source_format), identifiers].flatten.compact
      translation_files.collect!{|f| (Path.is_filename?(f, false) && options[:namespace]) ? Path.setup(f.gsub(/\[?NAMESPACE\]?/, options[:namespace])) : f }
    end

    if source_format
      source_index = begin
                       TSV.translation_index(translation_files, source_header, source_format)
                     rescue
                       TSV.translation_index(translation_files, original_source_header, source_format)
                     end
    end

    if target_format
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
                        if source_header
                          original_source_header.include?(source_header) ? original_source_header : source_header
                        else
                          original_source_header
                        end
                      end

    fields = original_field_headers
    final_target_field = if target_format
                     if m = original_target_header.match(/(.*) \(.*\)/)
                       m[1] + " (#{target_format})"
                     elsif m = field_headers.first.match(/(.*) \(.*\)/)
                       m[1] + " (#{target_format})"
                     else
                       target_format
                     end
                   else
                     target_header = field_headers.first
                     original_target_header.include?(target_header) ? original_target_header : target_header
                   end
    final_fields = [final_target_field] + original_field_headers[1..-1]

    if source_index.nil? && target_index.nil?
      if TSV === obj
        IndiferentHash.pull_keys options, :persist
        type = options[:type] || obj.type
        res = obj.reorder original_source_header, all_fields.values_at(*field_pos), **options.merge(type: type, merge: true)
      else
        res = TSV.open(obj, key_field: original_source_header, fields: all_fields.values_at(*field_pos), **options.merge(type: type))
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
      if source_index
        k = source_index[k]
        next if k.nil? or k.empty?
      end
      if target_index
        if Array === v[0]
          v[0] = target_index.values_at(*v[0])
          non_nil_pos = []
          v[0].each_with_index{|e,i| non_nil_pos << i unless e.nil? || (String === e) && e.empty? }
          v = v.collect{|l| l.values_at *non_nil_pos}
        else
          v[0] = target_index[v[0]]
          next if v[0].nil? or v[0].empty?
        end
      end
      [k, v]
    end

    transformer
  end

  def self.database(file, *args, **kwargs)
    persist_options = IndiferentHash.pull_keys kwargs, :persist

    database_persist_options = IndiferentHash.add_defaults persist_options.dup, persist: true, 
      prefix: "Association::Index", serializer: :double,
      other_options: kwargs  

    Persist.tsv(file, kwargs, engine: "BDB", persist_options: database_persist_options) do |data|
      tsv = open(file, *args, **kwargs)
      data.serializer =  TSVAdapter.serializer_module(tsv.type) if data.respond_to?(:serializer)
      if TSV::Transformer === tsv 
        tsv.tsv(merge: true, data: data) 
      elsif data.respond_to?(:persistence_path)
        data.merge!(tsv)
        tsv.annotate(data)
        data
      else
        tsv
      end
    end
  end
end
