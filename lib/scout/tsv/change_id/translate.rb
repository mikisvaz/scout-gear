module TSV

  def self.translation_path(file_fields, source, target)
    target_files = file_fields.select{|f,fields| fields.include? target }.collect{|file,f| file }
    source_files = file_fields.select{|f,fields| fields.include? source }.collect{|file,f| file }

    if (one_step = target_files & source_files).any?
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
          raise "Could not traverse identifier path from #{Log.fingerprint file_fields}"
        end
      end
    end
  end

  def self.translation_index(files, source, target, persist_options = {})
    return nil if source == target
    persist_options = IndiferentHash.add_defaults persist_options.dup, :persist => true, :prefix => "Translation index"

    target = Entity.formats.find(target) if target && defined?(Entity) && Entity.formats.find(target)
    source = Entity.formats.find(source) if source && defined?(Entity) && Entity.formats.find(source)

    file_fields = {}

    files = [files] unless Array === files

    files.each do |file|
      file_fields[file] = all_fields(file)
    end

    path = translation_path(file_fields, source, target)

    name = [source, target] * "->" + "  (#{files.length} files - #{Misc.digest(files)})"
    Persist.persist(name, "HDB", persist_options) do 
      index = path.inject(nil) do |acc,file|
        if acc.nil?
          if TSV === file
            tsv = file.key_field == source ? file : file.reorder(source)
          else
            tsv = TSV.open(file, :key_field => source)
          end
        else
          acc = acc.attach file
        end
      end
      index.slice([target]).to_single
    end
  end

  def self.translate(tsv, field, format, identifiers: nil, one2one: false, merge: true, stream: false, keep: false, persist_index: true)

    identifiers ||= tsv.identifiers
    index = translation_index([tsv, identifiers].flatten, field, format, persist: persist_index)

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

end
