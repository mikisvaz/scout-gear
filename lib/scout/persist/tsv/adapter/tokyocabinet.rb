require_relative 'base'
require_relative '../../engine/tokyocabinet'

module TKAdapter
  include TSVAdapter
  def self.extended(obj)
    obj.extend TSVAdapter
    obj
  end
end

module Persist
  def self.open_tokyocabinet(path, write, serializer = nil, tokyocabinet_class = TokyoCabinet::HDB)
    write = true unless File.exist? path

    FileUtils.mkdir_p File.dirname(path) unless File.exist?(File.dirname(path))

    database = ScoutCabinet.open(path, write, tokyocabinet_class)

    database.extend TKAdapter
    database.serializer ||= TSVAdapter.serializer_module(serializer)

    database
  end
end

Persist.save_drivers[:HDB] = proc do |file, content|
  if ScoutCabinet === content
    Open.mv(content.persistence_path, file)
    content.persistence_path = file
    content
  else
    data = ScoutCabinet.open(file, true, "HDB")
    content.annotate(data)
    data.extend TKAdapter
    data.merge!(content)
    data
  end
end

Persist.load_drivers[:HDB] = proc do |file|
  data = ScoutCabinet.open(file, false, "HDB")
  data.extend TKAdapter unless TKAdapter === data
  data
end

Persist.save_drivers[:BDB] = proc do |file, content|
  if ScoutCabinet === content
    Open.mv(content.persistence_path, file)
    content.persistence_path = file
    content
  else
    data = ScoutCabinet.open(file, true, "BDB")
    content.annotate(data)
    data.extend TKAdapter
    data.merge!(content)
    data
  end
end

Persist.load_drivers[:BDB] = proc do |file|
  data = ScoutCabinet.open(file, false, "BDB")
  data.extend TKAdapter unless TKAdapter === data
  data
end
