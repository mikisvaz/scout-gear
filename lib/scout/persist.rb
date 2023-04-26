require_relative 'persist/serialize'
require_relative 'persist/open'
require_relative 'persist/path'

module Persist
  class << self
    attr :cache_dir
    def cache_dir=(cache_dir)
      @cache_dir = Path === cache_dir ? cache_dir : Path.setup(cache_dir)
    end
    def cache_dir
      @cache_dir ||= Path.setup("var/cache/persistence")
    end

    attr_writer :lock_dir
    def lock_dir
      @lock_dir ||= Path.setup("var/cache/persist_locks")
    end
  end

  def self.persistence_path(name, options = {})
    options = IndiferentHash.add_defaults options, :dir => Persist.cache_dir
    other_options = IndiferentHash.pull_keys options, :other
    TmpFile.tmp_for_file(name, options, other_options)
  end

  def self.persist(name, type = :serializer, options = {}, &block)
    persist_options = IndiferentHash.pull_keys options, :persist 
    file = persist_options[:path] || options[:path] || persistence_path(name, options)

    update = options[:update] || persist_options[:update]
    update = Open.mtime(update) if Path === update
    update = Open.mtime(file) >= update ? false : true if Time === update

    if Open.exist?(file) && ! update
      Persist.load(file, type)
    else
      res = yield
      begin
        Open.rm(file)
        res = Persist.save(res, file, type)
      rescue
        raise $! unless options[:canfail]
        Log.debug "Could not persist #{type} on #{file}"
      end
      res
    end
  end

  def self.memory(name, *args, &block)
    self.persist(name, :memory, *args, &block)
  end

end
