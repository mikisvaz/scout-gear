require_relative 'meta_extension'
module NamedArray
  extend MetaExtension
  extension_attr :fields, :key

  def self.identify_name(names, selected)
    res = (Array === selected ? selected : [selected]).collect do |field|
      case field
      when nil
        0
      when Integer
        field
      when Symbol
        field == :key ? field : identify_name(names, field.to_s)
      when (names.nil? and String)
        if field =~ /^\d+$/
          identify_field(key_field, fields, field.to_i)
        else
          raise "No name information available and specified name not numeric: #{ field }"
        end
      when Symbol
        names.index{|f| f.to_s == field.to_s }
      when String
        pos = names.index{|f| f.to_s == field }
        next pos if pos
        if field =~ /^\d+$/
          next identify_names(names, field.to_i)
        end
        pos = names.index{|name| name.start_with?(field) }
        next pos if pos
        nil
      else
        raise "Field '#{ Log.fingerprint field }' was not understood. Options: (#{ Log.fingerprint names })"
      end
    end

    Array === selected ? res : res.first
  end

  def positions(fields)
    if Array ==  fields
      fields.collect{|field|
        NamedArray.identify_name(@fields, field)
      }
    else
      NamedArray.identify_name(@fields, fields)
    end
  end

  def [](key)
    pos = NamedArray.identify_name(@fields, key)
    super(pos)
  end

  def concat(other)
    super(other)
    self.fields.concat(other.fields) if NamedArray === other
    self
  end

  def to_hash
    hash = {}
    self.fields.zip(self) do |field,value|
      hash[field] = value
    end
    IndiferentHash.setup hash
  end
end
