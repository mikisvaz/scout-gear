require 'scout/open/lock'
require 'scout/annotation'

module TSVAdapter
  attr_accessor :persistence_path, :persistence_class, :closed, :writable, :serializer

  class << self
    attr_accessor :lock_dir
    def lock_dir
      @lock_dir ||= Path.setup('tmp/tsv_locks')
    end
  end

  ANNOTATION_ATTR_HASH_KEY = "__annotation_hash__"
  ANNOTATION_ATTR_HASH_SERIALIZER = Marshal

  def serializer=(serializer)
    @serializer = Symbol === serializer ? SERIALIZER_ALIAS[serializer] : serializer
  end

  def load_annotation_hash
    ANNOTATION_ATTR_HASH_SERIALIZER.load(StringIO.new(self.orig_get(ANNOTATION_ATTR_HASH_KEY)))
  end

  def save_annotation_hash
    self.close
    self.with_write do
      self.orig_set(ANNOTATION_ATTR_HASH_KEY, ANNOTATION_ATTR_HASH_SERIALIZER.dump(self.annotation_hash))
    end
  end

  def self.extended(base)
    if TSV === base
      base.instance_variable_get(:@annotations).push(:serializer)
      base.serializer = SERIALIZER_ALIAS[base.type] if base.serializer.nil?
      base.save_annotation_hash
    else
      begin
        TSV.setup(base, base.load_annotation_hash)
      rescue
        TSV.setup(base)
        base.save_annotation_hash
      end
    end
  end

  def []=(...) super(...); end
  def [](...) super(...); end
  def keys(...) super(...); end
  def each(...) super(...); end
  def size(...) super(...); end

  alias orig_set []=
  alias orig_get []
  alias orig_keys keys
  alias orig_each each
  alias orig_size size

  def [](key, clean = false)
    self.read_lock do
      v = super(key)
      return v if clean
      v = load_value(v)
      NamedArray.setup(v, @fields, key) unless @unnamed || ! (Array === v)
      v
    end
  end

  def []=(key, value, clean = false)
    self.write_lock do
      if clean
        super(key, value)
      else
        super(key, save_value(value))
      end
    end
  end

  def load_value(str)
    return nil if str.nil?
    return str if serializer.nil?
    return load_value(str.first) if Array === str
    serializer.load(str)
  end

  def save_value(value)
    return nil if value.nil?
    return value if serializer.nil?
    serializer.dump(value)
  end

  def keys_annotation_hash_key(*args)
    k = self.read_lock do
      orig_keys(*args)
    end

    if k[0] == ANNOTATION_ATTR_HASH_KEY
      k.slice(1,k.length)
    elsif k[-1] == ANNOTATION_ATTR_HASH_KEY
      k.slice(0,k.length-1)
    else
      k - [ANNOTATION_ATTR_HASH_KEY]
    end
  end
  alias keys keys_annotation_hash_key

  def each_annotation_hash_key(&block)
    self.read_lock do
      orig_each do |k,v|
        next if k == ANNOTATION_ATTR_HASH_KEY
        yield(k, load_value(v))
      end
    end
  end
  alias each each_annotation_hash_key

  def size_annotation_hash_key(*args)
    self.read_lock do
      orig_size(*args) - 1 # Discount the ANNOTATION_ATTR_HASH_KEY
    end
  end
  alias size size_annotation_hash_key

  alias length size

  def collect(&block)
    res = []
    if block_given?
      each do |k,v|
        res << yield(k, v)
      end
    else
      each do |k,v|
        res << [k, v]
      end
    end
    res
  end

  def values
    collect{|k,v| v }
  end

  alias map collect

  def closed?
    @closed
  end

  def write?
    @writable
  end

  def read?
    ! (write? || closed?)
  end

  def write(*args)
    begin
      begin
        super(*args) 
      rescue
      end
      @writable = true
    rescue NoMethodError
    end
  end


  def close(*args)
    begin
      super(*args)
      @closed = true
    rescue NoMethodError
    end
    self
  end

  def read(*args)
    begin
      super(*args)
    rescue NoMethodError
    end
  end

  def delete(key)
    self.write_lock do
      out(key)
    end
  end

  def lock
    return yield if @locked
    lock_filename = Persist.persistence_path(persistence_path, {:dir => TSVAdapter.lock_dir})
    Open.lock(lock_filename) do
      begin
        @locked = true
        yield
      ensure
        @locked = false
      end
    end
  end

  def lock_and_close
    lock do
      begin
        yield
      ensure
        close
      end
    end
  end

  def write_and_read
    if write?
      begin
        return yield
      ensure
        read
      end
    end

    lock do
      write(true) if closed? || !write?
      begin
        yield
      ensure
        read
      end
    end
  end

  def write_and_close
    if write?
      begin
        return yield
      ensure
        close unless @locked
      end
    end

    lock do
      write(true) if closed? || ! write?
      begin
        yield
      ensure
        close
      end
    end
  end

  def with_read(&block)
    if read? || write?
      return yield
    else
      read_and_close &block
    end
  end

  def with_write(&block)
    if write?
      return yield
    else
      if self.read?
        self.write_and_read(&block)
      else
        self.write_and_close(&block)
      end
    end
  end

  def read_and_close
    if read? || write?
      begin
        return yield
      ensure
        close unless @locked
      end
    end

    lock do
      read true if closed? || ! read?
      begin
        yield
      ensure
        close
      end
    end
  end

  def read_lock
    read if closed?
    if read? || write?
      return yield
    end

    lock do
      close
      read true
      begin
        yield
      end
    end
  end

  def write_lock
    write if closed?
    if write?
      return yield
    end

    lock do
      close
      write true
      begin
        yield
      end
    end
  end

  def merge!(hash)
    hash.each do |key,values|
      self[key] = values
    end
  end

  def range(*args)
    begin
      self.read_lock do
        super(*args)
      end
    rescue
      []
    end
  end

  def include?(*args)
    self.read_lock do
      super(*args) #- TSV::ENTRY_KEYS.to_a
    end
  end

  MAX_CHAR = 255.chr

  def prefix(key)
    self.read_lock do
      range(key, 1, key + MAX_CHAR, 1)
    end
  end

  def get_prefix(key)
    keys = prefix(key)
    select(:key => keys)
  end

  def values_at(*keys)
    self.read_lock do
      keys.collect do |k|
        self[k]
      end
    end
  end
end
