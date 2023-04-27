require_relative '../open'
require_relative 'open'

module Persist
  TRUE_STRINGS = Set.new ["true", "True", "TRUE", "t", "T", "1", "yes", "Yes", "YES", "y", "Y", "ON", "on"] unless defined? TRUE_STRINGS

  class << self
    attr_accessor :save_drivers, :load_drivers
    def save_drivers
      @save_drivers ||= {}
    end
    def load_drivers
      @load_drivers ||= {}
    end
  end

  def self.serialize(content, type)
    case type
    when nil, :string, :integer, :float, :boolean, :file, :path
      if IO === content || StringIO === content
        content.read
      else
        content.to_s
      end
    when :array
      content * "\n"
    when :yaml
      content.to_yaml
    when :json
      content.to_json
    when :marshal, :serializer
      Marshal.dump(content)
    else
      if m = type.to_s.match(/(.*)_array/)
        type = m[1].to_sym
        content.collect{|c| serialize(c, type) } * "\n"
      else
        raise "Persist does not know #{Log.fingerprint type}"
      end
    end
  end

  def self.deserialize(serialized, type)
    case type
    when nil, :string, :file, :stream
      serialized
    when :path
      Path.setup(serialized)
    when :integer
      serialized.to_i
    when :float
      serialized.to_f
    when :boolean
      TRUE_STRINGS.include? serialized
    when :array
      serialized.split("\n")
    when :yaml
      YAML.parse(serialized)
    when :json
      JSON.parse(serialized)
    when :marshal, :serializer
      Marshal.load(serialized)
    else
      if m = type.to_s.match(/(.*)_array/)
        type = m[1].to_sym
        new_content = serialized.split("\n")
        new_content.collect{|c| deserialize(c, type) }
      else
        raise "Persist does not know #{Log.fingerprint type}"
      end
    end
  end

  MEMORY = {}
  def self.save(content, file, type = :serializer)
    return if content.nil?
    type = MEMORY if type == :memory
    type = :serializer if type.nil?

    if Hash === type
      type[file] = content
      return
    end

    Log.debug "Save #{Log.fingerprint type} on #{file}"
    if save_drivers[type]
      Open.write(file, save_drivers[type].call(content))
      return
    end

    if IO === content || StringIO === content
      main, copy = Open.tee_stream_thread content
      t = Thread.new do
        Thread.current["name"] = "file saver: " + file
        Open.sensible_write(file, main)
      end
      ConcurrentStream.setup copy, :threads => t, :filename => file, :autojoin => true
    else
      serialized = serialize(content, type)
      Open.sensible_write(file, serialized)
      content
    end
  end

  def self.load(file, type = :serializer)
    file = file.find if Path === file
    type = MEMORY if type == :memory
    return unless Hash === type || Open.exist?(file) 
    type = :serializer if type.nil?

    Log.debug "Load #{Log.fingerprint type} on #{file}"
    if load_drivers[type]
      return load_drivers[type].call(file)
    end

    case type
    when :yaml
      Open.yaml(file)
    when :json
      Open.json(file)
    when :marshal, :serializer
      Open.marshal(file)
    when :stream
      Open.open(file)
    when :file
      value = Open.read(file)
      value.sub!(/^\./, File.dirname(file)) if value.start_with?("./")
      value
    when :file_array
      Open.read(file).split("\n").collect do |f|
        f.sub!(/^\./, File.dirname(file)) if f.start_with?("./")
        f
      end
    when Hash
      type[file]
    else
      deserialize(Open.read(file), type)
    end
  end
end
