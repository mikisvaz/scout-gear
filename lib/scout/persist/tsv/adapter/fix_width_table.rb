require_relative 'base'
require_relative '../../engine/fix_width_table'

module FWTAdapter
  include TSVAdapter

  def self.extended(base)
    base.extend TSVAdapter
    base
  end

  attr_accessor :pos_function

  def persistence_path=(value)
    @persistence_path = value
    @filename = value
  end

  def metadata_file
    @metadata_file ||= self.persistence_path + '.metadata'
  end

  def load_annotation_hash
    ANNOTATION_ATTR_HASH_SERIALIZER.load(Open.read(metadata_file, mode: 'b'))
  end

  def save_annotation_hash
    Open.write(metadata_file, ANNOTATION_ATTR_HASH_SERIALIZER.dump(self.annotation_hash), mode: 'wb')
  end

  def add(key, value)
    key = pos_function.call(key) if pos_function and not (@range and Array === key)
    value = save_value(value)
    super(key, value)
  end

  def add_range_point(key, value)
    key = pos_function.call(key) if pos_function
    value = save_value(value)
    super(key, value)
  end

  def [](key, clean = false)
    key = pos_function.call(key) if pos_function and not clean
    res = super(key)
    return nil if res.nil?
    res = res.collect{|r| load_value(r) }
    res.extend MultipleResult
    res
  end

  def <<(values)
    key, value = values
    self.add(key, value)
  end

  def include?(i)
    return true if Numeric === i and i < pos(@size)
    @annotations
    false
  end

  def size
    @size
  end

  def each
    read
    @size.times do |i|
      v = idx_value(i)
      yield i, v
    end
  end

  def keys
    []
  end
end

module Persist

  def self.open_fwt(path, value_size, range = false, serializer = nil, update = false, in_memory = false, &pos_function)
    FileUtils.mkdir_p File.dirname(path) unless File.exist?(File.dirname(path))

    database = FixWidthTable.new(path, value_size, range, update, in_memory, &pos_function)

    database.extend FWTAdapter

    database.pos_function = pos_function

    unless serializer == :clean
      TSV.setup database
      database.serializer ||= TSVAdapter.serializer_module(serializer)
    end

    database
  end
end

Persist.save_drivers[:fwt] = proc do |file, content|
  content.file.seek 0
  Misc.sensiblewrite(file, content.file.read)
end

Persist.load_drivers[:fwt] = proc do |file| 
  FixWidthTable.new file
end
