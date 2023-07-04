require 'scout/open/lock'
require 'scout/meta_extension'
require_relative 'serialize'

module TSVAdapter
  attr_accessor :persistence_path, :persistence_class, :closed, :writable, :serializer

  class << self
    attr_accessor :lock_dir
    def lock_dir
      @lock_dir ||= Path.setup('tmp/tsv_locks')
    end
  end

  EXTENSION_ATTR_HASH_KEY = "__extension_attr_hash__"
  EXTENSION_ATTR_HASH_SERIALIZER = Marshal

  def serializer=(serializer)
    @serializer = Symbol === serializer ? SERIALIZER_ALIAS[serializer] : serializer
  end

  def load_extension_attr_hash
    EXTENSION_ATTR_HASH_SERIALIZER.load(StringIO.new(self.orig_get(EXTENSION_ATTR_HASH_KEY)))
  end

  def save_extension_attr_hash
    self.orig_set(EXTENSION_ATTR_HASH_KEY, EXTENSION_ATTR_HASH_SERIALIZER.dump(self.extension_attr_hash))
  end

  def self.extended(base)
    return if base.respond_to?(:orig_set)

    class << base
      alias orig_set []=
        alias orig_get []

      def [](key)
        self.read_lock do
          load_value(super(key))
        end
      end

      def []=(key, value)
        self.write_lock do
          super(key, save_value(value))
        end
      end

      def load_value(str)
        return nil if str.nil?
        serializer.load(str)
      end

      def save_value(value)
        serializer.dump(value)
      end
    end

    if base.include?(EXTENSION_ATTR_HASH_KEY)
      TSV.setup(base, base.load_extension_attr_hash)
    else
      base.instance_variable_get(:@extension_attrs).push :serializer
      base.serializer = SERIALIZER_ALIAS[base.type] if base.serializer.nil?
      base.save_extension_attr_hash
    end
  end

  def keys(*args)
    k = self.read_lock do
      super(*args)
    end

    if k[0] == EXTENSION_ATTR_HASH_KEY
      k.slice(1,k.length)
    elsif k[-1] == EXTENSION_ATTR_HASH_KEY
      k.slice(0,k.length-1)
    else
      k - [EXTENSION_ATTR_HASH_KEY]
    end
  end

  def each(&block)
    self.read_lock do
      super do |k,v|
        next if k == EXTENSION_ATTR_HASH_KEY
        yield(k, load_value(v))
      end
    end
  end

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
      super(*args)
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
      res = begin
              yield
            ensure
              close
            end
      res
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
        self.write_and_read do
          return yield
        end
      else
        self.write_and_close do
          return yield
        end
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

  def size(*args)
    self.read_lock do
      super(*args)
    end
  end

  def values_at(*keys)
    self.read_lock do
      keys.collect do |k|
        self[k]
      end
    end
  end
end
