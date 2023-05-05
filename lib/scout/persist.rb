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
      return yield(file) if block.arity == 1
      res = yield
      begin
        Open.rm(file)

        if IO === res || StringIO === res
          tee_copies = options[:tee_copies] || 1
          main, *copies = Open.tee_stream_thread_multiple res, tee_copies + 1
          t = Thread.new do
            Thread.current.report_on_exception = false
            Thread.current["name"] = "file saver: " + file
            Open.sensible_write(file, main)
          end
          Thread.pass until t["name"]
          copies.each_with_index do |copy,i|
            next_stream = copies[i+1] if copies.length > i
            ConcurrentStream.setup copy, :threads => t, :filename => file, :autojoin => true, :next => next_stream
          end
          res = copies.first
        else
          pres = Persist.save(res, file, type)
          res = pres unless pres.nil?
        end
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
