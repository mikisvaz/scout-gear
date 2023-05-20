module TSV
  def self.change_key(source, new_key_field, identifiers: nil, one2one: false, stream: false)
    source = TSV::Parser.new source if String === source
    if source.identify_field(new_key_field).nil?
      identifiers = identifiers.nil? ? source.identifiers : identifiers
      new = source.attach(identifiers, fields: [new_key_field], insitu: false).change_key(new_key_field)
      return new
    end

    transformer = TSV::Transformer.new source
    transformer.key_field = new_key_field
    transformer.fields = [source.key_field] + source.fields - [new_key_field]
    transformer.traverse key_field: new_key_field, one2one: one2one do |k,v|
      [k, v]
    end

    stream ? transformer : transformer.tsv
  end

  def change_key(*args, **kwargs)
    TSV.change_key(self, *args, **kwargs)
  end

  def self.change_id(source, source_id, new_id, identifiers: nil, one2one: false, insitu: false)
    source = TSV::Parser.new source if String === source

    identifiers = identifiers.nil? ? source.identifiers : identifiers

    new_fields = source.fields.dup
    new_fields[new_fields.index(source_id)] = new_id
    return source.attach(identifiers, fields: [new_id], insitu: insitu).slice(new_fields)
  end

  def change_id(*args, **kwargs)
    TSV.change_id(self, *args, **kwargs)
  end
end
