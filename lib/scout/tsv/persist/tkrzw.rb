require 'tkrzw'
require_relative 'adapter'

module ScoutTKRZW
  attr_accessor :persistence_path, :persistence_class, :open_options

  def self.open(path, write = true, persistence_class = 'tkh', options = {})
    open_options = IndiferentHash.add_defaults options, truncate: true, num_buckets: 100, dbm: "HashDBM", sync_hard: true, encoding: "UTF-8"
  
    path = path.find if Path === path

    dir = File.dirname(File.expand_path(path))
    Open.mkdir(dir) unless File.exist?(dir)

    database = Persist::CONNECTIONS[[persistence_class, path]*":"] ||= Tkrzw::DBM.new

    database.close if database.open?

    database.open(path, write, open_options)

    database.extend ScoutTKRZW
    database.persistence_path ||= path
    database.open_options = open_options

    #Persist::CONNECTIONS[[persistence_class, path]*":"] = database

    database
  end

  def close
    @closed = true
    @writable = false
    super
  end

  def read(force = false)
    return if open? && ! writable? && ! force
    self.close if open?
    if !self.open(@persistence_path, false, @open_options)
      ecode = self.ecode
      raise "Open error: #{self.errmsg(ecode)}. Trying to open file #{@persistence_path}"
    end

    @writable = false
    @closed = false

    self
  end

  def write(force = true)
    return if open? && writable? && ! force
    self.close if self.open?

    if !self.open(@persistence_path, true, @open_options)
      ecode = self.ecode
      raise "Open error: #{self.errmsg(ecode)}. Trying to open file #{@persistence_path}"
    end

    @writable = true
    @closed = false

    self
  end

  def keys
    search("contain", "")
  end
end

Persist.save_drivers[:tkh] = proc do |file, content|
  data = ScoutTKRZW.open(file, true, "tkh")
  content.annotate(data)
  data.extend TSVAdapter
  data.merge!(content)
  data.close
  data.read
  data
end

Persist.load_drivers[:tkh] = proc do |file| 
  data = ScoutTKRZW.open(file, false, "tkh")
  data.extend TSVAdapter unless TSVAdapter === data
  data
end
