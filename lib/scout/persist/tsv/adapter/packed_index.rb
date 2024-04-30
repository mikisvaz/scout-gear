require_relative 'base'
require_relative '../../engine/packed_index'

module PKIAdapter
  include TSVAdapter

  attr_accessor :pos_function

  def self.extended(base)
    base.extend TSVAdapter
    base
  end

  def persistence_path=(value)
    @persistence_path = value
    @file = value
  end

  def metadata_file
    @metadata_file ||= self.persistence_path + '.metadata'
  end

  def load_annotation_hash
    ANNOTATION_ATTR_HASH_SERIALIZER.load(Open.read(metadata_file, mode: 'rb'))
  end

  def save_annotation_hash
    Open.write(metadata_file, ANNOTATION_ATTR_HASH_SERIALIZER.dump(self.annotation_hash), mode: 'wb')
  end

  def [](key, clean = false)
    key = pos_function.call(key) if pos_function and not clean
    res = super(key)
    res.extend MultipleResult unless res.nil?
    res
  end

  def value(pos)
    self.send(:[], pos, true)
  end

  def []=(key, value)
    add key, value
  end

  def add(key, value)
    key = pos_function.call(key) if pos_function 
    if Numeric === key
      @_last ||= -1
      skipped = key - @_last - 1
      skipped.times do
        self.send(:<<, nil)
      end
      @_last = key
    end
    self.send(:<<, value)
  end

  def add_range_point(key, value)
    key = pos_function.call(key) if pos_function
    super(key, value)
  end

  def include?(i)
    return true if Numeric === i and i < size
    false
  end

  def each
    size.times do |i|
      yield i, value(i)
    end
  end

  def keys
    []
  end
end

module Persist
  def self.open_pki(path, write, pattern, &pos_function)
    FileUtils.mkdir_p File.dirname(path) unless File.exist?(File.dirname(path))

    database = PackedIndex.new(path, write, pattern, &pos_function)
    database.extend PKIAdapter

    database.pos_function = pos_function

    database
  end
end
