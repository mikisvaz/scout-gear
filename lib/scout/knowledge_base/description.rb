class KnowledgeBase
  def self.doc_parse_up_to(str, pattern, keep = false)
    pre, _pat, _post = str.partition pattern
    if _pat
      [pre, (keep ? _pat << _post : _post)]
    else
      _post
    end
  end

  def self.doc_parse_chunks(str, pattern)
    parts = str.split(pattern)
    return {} if parts.length < 2
    databases = Hash[*parts[1..-1].collect{|v| v.strip }]
    databases.delete_if{|t,d| d.empty?}
    databases.transform_keys!(&:downcase)
    databases
  end

  def self.parse_knowledge_base_doc(doc)
    description, db_description = doc_parse_up_to doc, /^#/, true
    databases = doc_parse_chunks db_description, /^# (.*)/
    IndiferentHash.setup({:description => description.strip, :databases => databases})
  end

  def documentation_markdown
    return "" if @libdir.nil?
    file = @libdir['README.md'].find unless file.exists?
    if file.exists?
      file.read
    else
      ""
    end
  end

  def database_description_file(name)
    dir[name.to_s + '.md']
  end

  def knowledge_base_description_file(name)
    file = dir['README.md']
    return file if file.exists?

    file, options = registry[name]
    file = Path.setup(file.dup) unless file.nil? or Path === file
    source_readme = file.dirname['README.md'] if file
    return source_readme if source_readme  && source_readme.exists?
  end

  def description(name)
    return registered_options(name)[:description] if registered_options(name)[:description]

    return database_description_file(name).read if database_description_file(name).exist?

    if knowledge_base_description_file(name)
      KnowledgeBase.parse_knowledge_base_doc(knowledge_base_description_file(name).read)[:databases][name.to_s.downcase]
    end
  end

  def markdown(name)
    description = description(name)
    source_type = source_type(name)
    target_type = target_type(name)

    full_description = []
    empty_line = ''
    full_description << ("# " + Misc.humanize(name))
    full_description << empty_line

    source_formats = begin
                       source_index(name).key_field.split(',')
                     rescue
                       []
                     end

    target_formats = begin
                       target_index(name).key_field.split(',')
                     rescue
                       []
                     end

    if source_type
      full_description << "Source: #{source_type} - #{source(name)}"
    else
      full_description << "Source: #{source(name)}"
    end
    #full_description.last << ". Accepted formats: #{source_formats*", "}" if source_formats.any?

    if target_type
      full_description << "Target: #{target_type} - #{target(name)}"
    else
      full_description << "Target: #{target(name)}"
    end
    #full_description.last << ". Accepted formats: #{target_formats*", "}" if target_formats.any?

    if undirected?(name)
      full_description << "Undirected database, source and target can be reversed."
    end

    if description
      full_description << empty_line
      full_description << description
      full_description << empty_line
    end

    full_description * "\n"
  end
end
