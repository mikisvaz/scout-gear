class Sharder
  attr_accessor :persistence_path, :shard_function, :databases, :closed, :writable, :mutex, :db_type, :persist_options

  def initialize(persistence_path, write=false, db_type=nil, persist_options={}, &block)
    @shard_function = persist_options[:shard_function] || block
    @persist_options = persist_options
    @persistence_path = Path.setup(persistence_path)
    @mutex = Mutex.new
    @writable = write
    @db_type = db_type

    if write
      @databases = {} 
    end
  end

  def persistence_path=(path)
    @persistence_path = path
    databases.values.each{|db| db.persistence_path = File.join(path, File.basename(db.persistence_path))}
  end

  def databases
    @databases ||= begin
                     hash = {}
                     @persistence_path.glob('shard-*').each do |f|
                       next if f.end_with?('.metadata')
                       shard = File.basename(f).match(/shard-(.*)/)[1]
                       hash[shard] = Persist.open_database(f, false, :clean, db_type, @persist_options)
                     end
                     hash
                   end
  end

  def database(key)
    shard = shard_function.call(key)
    if databases.include? shard
      databases[shard]
    else
      database = databases[shard] ||= begin
                                        path = File.join(persistence_path, 'shard-' << shard.to_s)
                                        (writable or File.exist?(path)) ? Persist.open_database(path, (File.exist?(path) ? false : writable), :clean, db_type, @persist_options) : nil
                                      end
      Log.warn "Database #{ path } missing" if database.nil?
      database
    end
  end

  MAX_CHAR = 255.chr

  def prefix(key)
    range(key, 1, key + MAX_CHAR, 1)
  end

  def get_prefix(key)
    keys = prefix(key)
    select(:key => keys)
  end

  def closed?
    @closed
  end

  def close
    @closed = true
    super
  end

  def read(force = false)
    raise "SIOT"
    return if not write? and not closed and not force
    self.close
    databases.each{|d| d.read }
    @writable = false
    @closed = false
    self
  end

  def write(force = true)
    return if write? and not closed and not force
    self.close

    databases.each{|d| d.write }

    @writable = true
    @closed = false
    self
  end

  def write?
    @writable
  end

  def read?
    ! write?
  end

  def range(*args)
    databases.values.inject([]) do |acc,database|
      acc.concat database.range(*args) if TokyoCabinet::BDB === database
      acc
    end
  end

  def each
    databases.values.each do |database|
      database.each do |k,v|
        yield k, v
      end
    end
  end

  def include?(key)
    self[key] != nil
  end

  def collect
    res = []
    each do |key, value|
      res << if block_given?
               yield key, value
      else
        [key, value]
      end
    end
    res
  end

  def write_and_read
    lock_filename = Persist.persistence_path(File.join(persistence_path, 'write'), {:dir => TSV.lock_dir})
    Misc.lock(lock_filename) do
      @mutex.synchronize do
        write if @closed or not write?
        res = begin
                yield
              ensure
                read
              end
        res
      end
    end
  end

  def write_and_close
    lock_filename = Persist.persistence_path(File.join(persistence_path, 'write'), {:dir => TSV.lock_dir})
    Misc.lock(lock_filename) do
      @mutex.synchronize do
        write if @closed or not write?
        res = begin
                yield
              ensure
                close
              end
        res
      end
    end
  end

  def read_and_close
    @mutex.synchronize do
      read if @closed or not read?
      res = begin
              yield
            ensure
              close
            end
      res
    end
  end

  def merge!(hash)
    hash.each do |key,values|
      self[key] = values
    end
  end

  def keys
    databases.values.collect{|d| d.keys }
  end

  def []=(key, value, clean = false)
    database(key).send(:[]=, key, value)
  end

  def [](key, clean=false)
    database = database(key)
    return nil if database.nil?
    database.send(:[], key)
  end

  #def <<(p)
  #  return if p.nil?
  #  self[p.first] = p.last
  #end

  def <<(values)
    key, rest = values
    database(key) << values
  end

  def write
    databases.values.each{|database| database.write }
  end

  def read(force = false)
    databases.values.each{|database| database.read(force) }
  end

  def close
    databases.values.each{|database| database.close }
  end

  def size
    databases.inject(0){|acc,i| 
      shard, db = i; 
      acc += db.size 
    }
  end
end

