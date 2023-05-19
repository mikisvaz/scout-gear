require_relative 'meta_extension'
module NamedArray
  extend MetaExtension
  extension_attr :fields, :key

  def self.identify_name(names, selected)
    res = (Array === selected ? selected : [selected]).collect do |field|
      case field
      when nil
        0
      when Range
        field
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
        pos = names.index{|name| String === name && name.include?('(' + field + ')') }
        next pos if pos
        nil
      else
        raise "Field '#{ Log.fingerprint field }' was not understood. Options: (#{ Log.fingerprint names })"
      end
    end

    Array === selected ? res : res.first
  end

  def identify_name(selected)
    NamedArray.identify_name(fields, selected)
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
    return nil if pos.nil?
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

  def values_at(*positions)
    super(*identify_name(positions))
  end

  def self._zip_fields(array, max = nil)
    return [] if array.nil? or array.empty? or (first = array.first).nil?

    max = array.collect{|l| l.length }.max if max.nil?

    rest = array[1..-1].collect{|v|
      v.length == 1 & max > 1 ? v * max : v
    }

    first = first * max if first.length == 1 and max > 1

    first.zip(*rest)
  end

  def self.zip_fields(array)
    if array.length < 10000
      _zip_fields(array)
    else
      zipped_slices = []
      max = array.collect{|l| l.length}.max
      array.each_slice(10000) do |slice|
        zipped_slices << _zip_fields(slice, max)
      end
      new = zipped_slices.first
      zipped_slices[1..-1].each do |rest|
        rest.each_with_index do |list,i|
          new[i].concat list
        end
      end
      new
    end
  end

  def self.add_zipped(source, new)
    source.zip(new).each do |s,n|
      s << n
    end
    source
  end
end
