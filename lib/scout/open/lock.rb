require_relative '../path'
require_relative '../log'
require_relative '../exceptions'
require_relative 'lock/lockfile'

module Open
  def self.thread_in_lock(t)
    t.backtrace.select{|l| l.include?("lockfile") }.any?
  end

  def self.unlock_thread(t, exception = nil)
    while t.alive? && t.backtrace.select{|l| l.include?("lockfile") }.any?
      iii :UNLOCK
      t.raise(exception)
      Log.stack t.backtrace
      locks = t["locks"]
      return if locks.nil? || locks.empty?
      locks.each do |lock|
        lock.unlock if lock.locked?
        Open.rm(lock.path)
      end
      iii Thread.current
      Thread.list.each{|t| iii [t, t["locks"]]; Log.stack t.backtrace }
      Log.stack t.backtrace
    end
  end


  def self.lock(file, unlock = true, options = {})
    unlock, options = true, unlock if Hash === unlock
    return yield if file.nil? and not Lockfile === options[:lock]

    if Lockfile === file
      lockfile = file
    else
      file = file.find if Path === file
      FileUtils.mkdir_p File.dirname(File.expand_path(file)) unless File.exist? File.dirname(File.expand_path(file))

      case options[:lock]
      when Lockfile
        lockfile = options[:lock]
      when FalseClass
        lockfile = nil
        unlock = false
      when Path, String
        lock_path = options[:lock].find
        lockfile = Lockfile.new(lock_path, options)
      else
        lock_path = File.expand_path(file + '.lock')
        lockfile = Lockfile.new(lock_path, options)
      end
    end

    begin
      lockfile.lock unless lockfile.nil? || lockfile.locked?
    rescue Aborted, Interrupt
      raise LockInterrupted
    end

    iii Thread.current["lock_exception"] if Thread.current["lock_exception"]
    raise Thread.current["lock_exception"] if Thread.current["lock_exception"]

    res = nil

    begin
      res = yield lockfile
    rescue KeepLocked
      unlock = false
      res = $!.payload
    ensure
      if unlock 
        begin
          if lockfile.locked?
            lockfile.unlock 
          end
          iii Thread.current["lock_exception"] if Thread.current["lock_exception"]
          raise Thread.current["lock_exception"] if Thread.current["lock_exception"]
        rescue Exception
          Log.warn "Exception unlocking: #{lockfile.path}"
          Log.exception $!
        end
      end
    end

    res
  end
end
