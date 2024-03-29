require 'tokyocabinet'
require_relative 'adapter'
require_relative 'serialize'

module ScoutCabinet
  attr_accessor :persistence_path, :persistence_class

  def self.open(path, write, tokyocabinet_class = TokyoCabinet::HDB)
    path = path.find if Path === path
    if String === tokyocabinet_class && tokyocabinet_class.include?(":big")
      big = true
      tokyocabinet_class = tokyocabinet_class.split(":").first
    else
      big = false
    end

    dir = File.dirname(File.expand_path(path))
    Open.mkdir(dir) unless File.exist?(dir)

    tokyocabinet_class = tokyocabinet_class.to_s if Symbol === tokyocabinet_class
    tokyocabinet_class = TokyoCabinet::HDB if tokyocabinet_class == "HDB" or tokyocabinet_class.nil?
    tokyocabinet_class = TokyoCabinet::BDB if tokyocabinet_class == "BDB"

    # Hack - Ignore warning: undefining the allocator of T_DATA class
    # TokyoCabinet::HDB_data
    database = Log.ignore_stderr do Persist::CONNECTIONS[path] ||= tokyocabinet_class.new end

    if big and not Open.exists?(path)
      database.tune(nil, nil, nil, tokyocabinet_class::TLARGE | tokyocabinet_class::TDEFLATE) 
    end

    flags = (write ? tokyocabinet_class::OWRITER | tokyocabinet_class::OCREAT : tokyocabinet_class::OREADER)
    database.close 

    if !database.open(path, flags)
      ecode = database.ecode
      raise "Open error: #{database.errmsg(ecode)}. Trying to open file #{path}"
    end

    database.extend ScoutCabinet
    database.persistence_path ||= path
    database.persistence_class = tokyocabinet_class

    database.open(path, tokyocabinet_class::OREADER)

    database.define_singleton_method(:fingerprint){ "#{self.persistence_class}:#{self.persistence_path}" }

    Persist::CONNECTIONS[path] = database

    database
  end

  def close
    @closed = true
    @writable = false
    super
  end

  def read(force = false)
    return if ! @writable && ! @closed && ! force
    self.close
    if !self.open(@persistence_path, persistence_class::OREADER)
      ecode = self.ecode
      raise "Open error: #{self.errmsg(ecode)}. Trying to open file #{@persistence_path}"
    end

    @writable = false
    @closed = false

    self
  end

  def write?
    @writable
  end

  def closed?
    @closed
  end


  def write(force = true)
    return if write? && ! closed? && ! force
    self.close

    if !self.open(@persistence_path, persistence_class::OWRITER)
      ecode = self.ecode
      raise "Open error: #{self.errmsg(ecode)}. Trying to open file #{@persistence_path}"
    end

    @writable = true
    @closed = false

    self
  end

  def write_and_read
    begin
      write
      yield
    ensure
      read
    end
  end

  def write_and_close
    begin
      write
      yield
    ensure
      close
    end
  end
  #def self.open_tokyocabinet(path, write, serializer = nil, tokyocabinet_class = TokyoCabinet::HDB)
  #  raise
  #  write = true unless File.exist? path

  #  FileUtils.mkdir_p File.dirname(path) unless File.exist?(File.dirname(path))

  #  database = Persist::TCAdapter.open(path, write, tokyocabinet_class)

  #  unless serializer == :clean
  #    TSV.setup database
  #    database.write_and_read do
  #      database.serializer = serializer
  #    end if serializer && database.serializer != serializer
  #  end

  #  database
  #end
end

module Persist
  def self.open_tokyocabinet(path, write, serializer = nil, tokyocabinet_class = TokyoCabinet::HDB)
    write = true unless File.exist? path

    FileUtils.mkdir_p File.dirname(path) unless File.exist?(File.dirname(path))

    database = ScoutCabinet.open(path, write, tokyocabinet_class)

    database.extend TSVAdapter
    database.serializer = TSVAdapter::SERIALIZER_ALIAS[serializer] || serializer

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
    data.extend TSVAdapter
    data.merge!(content)
    data
  end
end

Persist.load_drivers[:HDB] = proc do |file| 
  data = ScoutCabinet.open(file, false, "HDB")
  data.extend TSVAdapter unless TSVAdapter === data
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
    data.extend TSVAdapter
    data.merge!(content)
    data
  end
end

Persist.load_drivers[:BDB] = proc do |file| 
  data = ScoutCabinet.open(file, false, "BDB")
  data.extend TSVAdapter unless TSVAdapter === data
  data
end
