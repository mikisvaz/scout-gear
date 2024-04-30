require 'tokyocabinet'

module ScoutCabinet
  attr_accessor :persistence_path, :persistence_class

  def self.open(path, write = true, tokyocabinet_class = TokyoCabinet::HDB)
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

  def self.importtsv(database, stream)
    begin
      bin = case database
            when TokyoCabinet::HDB
              'tchmgr'
            when TokyoCabinet::BDB
              'tcbmgr'
            else
              raise "Database not HDB or BDB: #{Log.fingerprint database}"
            end
      
      database.close
      CMD.cmd("#{bin} version", :log => false)
      FileUtils.mkdir_p File.dirname(database.persistence_path)
      CMD.cmd("#{bin} importtsv '#{database.persistence_path}'", :in => stream, :log => false, :dont_close_in => true)
    rescue
      Log.debug("tchmgr importtsv failed for: #{database.persistence_path}")
    end
  end

  class << self
    alias load_stream importtsv
  end

  def importtsv(stream)
    ScoutCabinet.load_stream(self, stream)
  end

  alias load_stream importtsv
end
