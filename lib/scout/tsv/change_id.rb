require_relative 'change_id/translate'

module TSV
  def self.change_key(source, new_key_field, identifiers: nil, one2one: false, merge: true, stream: false, keep: false, persist_identifiers: nil)
    source = TSV::Parser.new source if String === source
    identifiers = source.identifiers if identifiers.nil? and source.respond_to?(:identifiers)
    if identifiers && source.identify_field(new_key_field, strict: true).nil?
      identifiers = identifiers.nil? ? source.identifiers : identifiers
      if Array === identifiers
        identifiers = identifiers.select{|f| f.identify_field(new_key_field) }.last
      end
      new = source.attach(identifiers, fields: [new_key_field], insitu: false, one2one: true, persist_input: persist_identifiers)
      new = new.change_key(new_key_field, keep: keep, stream: stream, one2one: one2one, merge: merge)
      return new
    end

    fields = source.fields.dup - [new_key_field]
    fields.unshift source.key_field if keep
    transformer = TSV::Transformer.new source
    transformer.key_field = new_key_field
    transformer.fields = fields
    transformer.traverse key_field: new_key_field, fields: fields, one2one: one2one, unnamed: true do |k,v|
      [k, v]
    end

    stream ? transformer : transformer.tsv(merge: merge, one2one: one2one)
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
