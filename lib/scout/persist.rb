require_relative 'persist/serialize'

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
    file = persistence_path(name, options)

    if Open.exist?(file) && ! options[:update] && ! persist_options[:update]
      Persist.load(file, type)
    else
      res = yield

      if type === :stream
        main, copy = Open.tee_stream_thread res
        t = Thread.new do
          Thread.current["name"] = "file saver: " + file
          Persist.save(main, file, :string)
        end
        res = ConcurrentStream.setup copy, :threads => t, :filename => file, :autojoin => true
      else
        Persist.save(res, file, type)
      end

      res
    end
  end

end
