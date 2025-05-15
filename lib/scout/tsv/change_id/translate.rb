module TSV

  def self.identify_field_in_obj(obj, field)
    case obj
    when TSV
      obj.identify_field(field)
    when TSV::Parser, TSV::Dumper
      TSV.identify_field(obj.key_field, obj.fields, field)
    when Path, String
      all_fields = TSV.parse_header(obj)["all_fields"]
      identify_field_in_obj(all_fields, field)
    when Array
      key_field, *fields = obj
      TSV.identify_field(key_field, fields, field)
    end
  end

  def self.translation_path(file_fields, source, target)
    target_files = file_fields.select{|f,fields| identify_field_in_obj(fields, target) }.collect{|file,f| file }
    if source.nil?
      source_files = file_fields.keys
    else
      source_files = file_fields.select{|f,fields| identify_field_in_obj(fields, source) }.collect{|file,f| file }
    end

    if source && (one_step = target_files & source_files).any?
      [one_step.first]
    else
      source_fields = file_fields.values_at(*source_files).flatten
      target_fields = file_fields.values_at(*target_files).flatten
      if (common_fields = source_fields & target_fields).any?
        source_file = source_files.select{|file| fields = file_fields[file]; (fields & common_fields).any? }.collect{|file,f| file }.first
        target_file = target_files.select{|file| fields = file_fields[file]; (fields & common_fields).any? }.collect{|file,f| file }.first
        [source_file, target_file]
      else
        file_fields.select{|f,fields| (fields & source_fields).any? && (fields & target_fields).any? }
        middle_file, middle_fields = file_fields.select{|f,fields| (fields & source_fields).any? && (fields & target_fields).any? }.first
        if middle_file
          source_file = source_files.select{|file| fields = file_fields[file]; (fields & middle_fields).any? }.collect{|file,f| file }.first
          target_file = target_files.select{|file| fields = file_fields[file]; (fields & middle_fields).any? }.collect{|file,f| file }.first
          [source_file, middle_file, target_file]
        else
          raise "Could not traverse identifier path from #{Log.fingerprint source} to #{Log.fingerprint target}. #{file_fields.empty? ? "No identifier files" : Log.fingerprint(file_fields)}"
        end
      end
    end
  end

  def self.translation_index(files, source, target, persist_options = {})
    return nil if source == target
    persist_options = IndiferentHash.add_defaults persist_options.dup, :persist => true, :prefix => "Translation index"

    file_fields = {}

    files = [files] unless Array === files

    files.each do |file|
      #next if Path === file && ! Open.exist?(file)
      Path.setup file if String === file and not Path === file
      begin
        file = file.produce if Path === file
        raise "Could no produce file" if FalseClass === file
      rescue
        Log.warn $!.message
        next
      end
      file = file.find if Path === file
      file_fields[file] = all_fields(file)
    end

    begin
      path = translation_path(file_fields, source, target)
    rescue
      exception = $!
      begin
        path = translation_path(file_fields, source, target)
      rescue
        raise exception
      end
    end

    name = [source || "all", target] * "->" + " (#{files.length} files - #{Misc.digest(files)})"
    second_target = if path.length == 1
                      target
                    else
                      file1, file2 = path.values_at 0, 1
                      pos = NamedArray.identify_name(TSV.all_fields(file1), TSV.all_fields(file2))
                      TSV.all_fields(file1)[pos.compact.first]
                    end
    Persist.persist(name, "HDB", persist_options) do 
      index = path.inject(nil) do |acc,file|
        if acc.nil?
          if source.nil?
            if TSV === file
              acc = file.index target: second_target
            else
              acc = TSV.index(file, target: second_target)
            end
          else
            if TSV === file
              acc = (file.key_field == source || source.nil?) ? file.annotate(file.dup) : file.reorder(source)
            else
              acc = TSV.open(file, key_field: source)
            end
          end
        else
          acc = acc.attach file, insitu: false
        end

        acc
      end
      index.slice([target]).to_single
    end
  end

  def self.translate(tsv, field, format, identifiers: nil, one2one: false, merge: true, stream: false, keep: false, persist_index: true)

    identifiers ||= tsv.identifier_files
    index = translation_index([tsv, identifiers].flatten.compact, field, format, persist: persist_index)

    key_field, *fields = TSV.all_fields(tsv)
    if field == key_field
      new_key_field = format
      new_fields = fields
    else
      new_key_field = key_field
      new_fields = fields.collect{|f| f == field ? format : f }
    end

    field_pos = new_key_field == key_field ? new_fields.index(format) : :key

    transformer = TSV::Transformer.new tsv
    transformer.key_field = new_key_field
    transformer.fields = new_fields
    transformer.traverse one2one: one2one, unnamed: true do |k,v|
      if field_pos == :key
        [index[k], v]
      else
        v = v.dup
        if Array === v[field_pos]
          v[field_pos] = index.values_at(*v[field_pos]).compact
        else
          v[field_pos] = index[v[field_pos]]
        end
        [k, v]
      end
    end

    stream ? transformer : transformer.tsv(merge: merge, one2one: one2one)
  end

  def translate(*args, **kwargs)
    TSV.translate(self, *args, **kwargs)
  end

end
