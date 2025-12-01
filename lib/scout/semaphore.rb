begin
  require 'inline'
  require 'fileutils'
  continue = true
rescue Exception
  Log.warn "The RubyInline gem could not be loaded: semaphore synchronization will not work"
  continue = false
end

if continue
  module ScoutSemaphore
    class SemaphoreInterrupted < TryAgain; end

    inline(:C) do |builder|
      builder.prefix <<-EOF
  #include <unistd.h>
  #include <stdio.h>
  #include <stdlib.h>
  #include <semaphore.h>
  #include <time.h>
  #include <assert.h>
  #include <errno.h>
  #include <signal.h>
  #include <fcntl.h>
      EOF

      # Create a named semaphore. Return 0 on success, -errno on error.
      builder.c_singleton <<-EOF
  int create_semaphore_c(char* name, int value){
    sem_t* sem;
    sem = sem_open(name, O_CREAT, S_IRWXU|S_IRWXG|S_IRWXO, value);
    if (sem == SEM_FAILED){
      return -errno;
    }
    /* close our handle; the semaphore lives on until unlinked and all handles closed */
    sem_close(sem);
    return 0;
  }
      EOF

      # Unlink (remove) a named semaphore. Return 0 on success, -errno on error.
      builder.c_singleton <<-EOF
  int delete_semaphore_c(char* name){
    int ret = sem_unlink(name);
    if (ret == -1) {
      return -errno;
    }
    return 0;
  }
      EOF

      # Wait (sem_wait) on a named semaphore. Return 0 on success, -errno on error.
      builder.c_singleton <<-EOF
  int wait_semaphore_c(char* name){
    sem_t* sem;
    sem = sem_open(name, 0);
    if (sem == SEM_FAILED){
      return -errno;
    }

    int ret;
    /* retry if interrupted by signal; stop on success or other error */
    do {
      ret = sem_wait(sem);
    } while (ret == -1 && errno == EINTR);

    if (ret == -1){
      int e = errno;
      sem_close(sem);
      return -e;
    }

    sem_close(sem);
    return 0;
  }
      EOF

      # Post (sem_post) on a named semaphore. Return 0 on success, -errno on error.
      builder.c_singleton <<-EOF
  int post_semaphore_c(char* name){
    sem_t* sem;
    sem = sem_open(name, 0);
    if (sem == SEM_FAILED){
      return -errno;
    }

    int ret;
    /* retry post if interrupted */
    do {
      ret = sem_post(sem);
    } while (ret == -1 && errno == EINTR);

    if (ret == -1) {
      int e = errno;
      sem_close(sem);
      return -e;
    }

    sem_close(sem);
    return 0;
  }
      EOF

    end

    SEM_MUTEX = Mutex.new

    def self.ensure_semaphore_name(file)
      # Ensure a valid POSIX named semaphore name: must start with '/'
      s = file.to_s.dup
      # strip leading slashes and replace other slashes with underscores, then prepend single '/'
      s.gsub!(%r{^/+}, '')
      s = '/' + s.gsub('/', '_')
      s
    end

    def self.exists?(name)
      file = File.join('/dev/shm', 'sem.' + name[1..-1])
      Open.exists? file
    end

    # Errno numeric lists
    RETRIABLE_ERRNOS = [
      Errno::ENOENT,
      Errno::EIDRM,
      Errno::EAGAIN,
      Errno::EMFILE,
      Errno::ENFILE,
      Errno::EINTR
    ].map { |c| c.new.errno }

    FATAL_ERRNOS = [
      Errno::EINVAL,
      Errno::EACCES
    ].map { |c| c.new.errno }

    # Generic retry wrapper with exponential backoff + jitter
    def self.with_retry(max_attempts: 6, base_delay: 0.01, max_delay: 1.0, jitter: 0.5, retriable: RETRIABLE_ERRNOS)
      attempts = 0
      while true
        attempts += 1
        ret = yield
        # caller expects 0 on success, negative errno on failure
        return ret if ret >= 0

        err = -ret
        # don't retry if it's clearly fatal or not in retriable list
        if FATAL_ERRNOS.include?(err) || attempts >= max_attempts || !retriable.include?(err)
          return ret
        end

        # exponential backoff with jitter
        base = base_delay * (2 ** (attempts - 1))
        sleep_time = [base, max_delay].min
        # add jitter in range [0, jitter * sleep_time)
        sleep_time += rand * jitter * sleep_time

        Log.warn "Semaphore operation failed (errno=#{err}), retrying in #{'%.3f' % sleep_time}s (attempt #{attempts}/#{max_attempts})"
        sleep(sleep_time)
      end
    end

    # Try to create the semaphore while holding a per-semaphore lock to avoid races
    def self.ensure_or_create(name, size = 1)
      # Normalize and make a safe lock path under Scout.tmp.semaphore_locks
      lock_dir = if defined?(Scout) && Scout.respond_to?(:tmp) && Scout.tmp.respond_to?(:semaphore_locks)
                   Scout.tmp.semaphore_locks
                 else
                   File.join('/tmp', 'scout', 'semaphore_locks')
                 end

      FileUtils.mkdir_p(lock_dir) unless File.exist?(lock_dir)

      lock_base = File.join(lock_dir, name.gsub(%r{^/+}, '').gsub('/', '_'))

      begin
        Open.lock(lock_base) do |_lf|
          # If someone else created it while waiting for the lock, we're done
          return true if self.exists?(name)

          Log.info "Semaphore #{name} missing; creating under lock #{lock_base}"
          begin
            # call the lower-level C create and let create_semaphore perform checks/retries
            ret = ScoutSemaphore.create_semaphore_c(name, size)
            if ret < 0
              Log.warn "create_semaphore_c failed for #{name}: errno=#{-ret}"
              return false
            end

            # best-effort: ensure the file shows up
            unless self.exists?(name)
              Log.warn "Semaphore #{name} created but /dev/shm entry not visible"
            end

            Log.info "Semaphore #{name} created"
            return true
          rescue Exception => e
            Log.warn "Exception while creating semaphore #{name}: #{e.message}"
            return false
          end
        end
      rescue Exception => e
        Log.warn "Failed to acquire creation lock for #{name}: #{e.message}"
        return false
      end
    end

    # Safe wrappers that raise SystemCallError on final failure
    def self.create_semaphore(name, value, **opts)
      ret = with_retry(**opts) { ScoutSemaphore.create_semaphore_c(name, value) }
      # After creation attempt, make sure the /dev/shm entry exists (cluster may remove entries)
      raise SystemCallError.new("Semaphore missing (#{name})") unless self.exists?(name)
      if ret < 0
        raise SystemCallError.new("create_semaphore(#{name}) failed", -ret)
      end
      ret
    end

    def self.delete_semaphore(name, **opts)
      ret = with_retry(**opts) { ScoutSemaphore.delete_semaphore_c(name) }
      if ret < 0
        Log.warn("delete_semaphore(#{name}) failed")
      end
      ret
    end

    def self.wait_semaphore(name, **opts)
      # Try a normal wait first
      ret = with_retry(**opts) { ScoutSemaphore.wait_semaphore_c(name) }

      if ret < 0
        err = -ret
        # If semaphore missing or removed, try to recreate it under a lock and retry once
        if err == Errno::ENOENT.new.errno || err == Errno::EIDRM.new.errno
          Log.warn "wait_semaphore: semaphore #{name} appears missing (errno=#{err}); attempting recreate"
          created = ensure_or_create(name, opts.fetch(:create_size, 1))
          if created
            # retry the wait after creating
            ret = with_retry(**opts) { ScoutSemaphore.wait_semaphore_c(name) }
          end
        end
      end

      if ret < 0
        err = -ret
        if err == Errno::EINTR.new.errno
          raise SemaphoreInterrupted
        else
          raise SystemCallError.new("wait_semaphore(#{name}) failed", err)
        end
      end

      ret
    end

    def self.post_semaphore(name, **opts)
      # Try normal post first
      ret = with_retry(**opts) { ScoutSemaphore.post_semaphore_c(name) }

      if ret < 0
        err = -ret
        # If semaphore missing or removed, try to recreate it under a lock and then post
        if err == Errno::ENOENT.new.errno || err == Errno::EIDRM.new.errno
          Log.warn "post_semaphore: semaphore #{name} appears missing (errno=#{err}); attempting recreate"
          created = ensure_or_create(name, opts.fetch(:create_size, 1))
          if created
            ret = with_retry(**opts) { ScoutSemaphore.post_semaphore_c(name) }
          end
        end
      end

      if ret < 0
        raise SystemCallError.new("post_semaphore(#{name}) failed", -ret)
      end
      ret
    end

    def self.synchronize(sem)
      # Ensure name is normalized (caller should pass normalized name, but be safe)
      sem = ensure_semaphore_name(sem)

      # wait_semaphore returns 0 on success or -errno on error
      begin
        ScoutSemaphore.wait_semaphore(sem)
      rescue SemaphoreInterrupted
        raise
      rescue SystemCallError => e
        # bubble up for callers to handle
        raise
      end

      begin
        yield
      ensure
        begin
          ScoutSemaphore.post_semaphore(sem)
        rescue SystemCallError => e
          # Log but don't raise from ensure
          # Log.warn "post_semaphore(#{sem}) failed in ensure: #{e.message}"

          # Actually, do raise
          raise e
        end
      end
    end

    def self.with_semaphore(size, file = nil)
      if file.nil?
        file = "/scout-" + Misc.digest(rand(100000000000).to_s)[0..10]
      else
        # ensure valid POSIX name
        file = ensure_semaphore_name(file)
      end

      begin
        Log.debug "Creating semaphore (#{ size }): #{file}"
        begin
          ScoutSemaphore.create_semaphore(file, size)
        rescue SystemCallError => e
          Log.error "Failed to create semaphore #{file}: #{e.message}"
          raise
        end

        yield file
      ensure
        Log.debug "Removing semaphore #{ file }"
        begin
          ScoutSemaphore.delete_semaphore(file)
        rescue SystemCallError => e
          Log.warn "delete_semaphore(#{file}) failed: #{e.message}"
        end
      end
    end

    def self.fork_each_on_semaphore(elems, size, file = nil)

      TSV.traverse elems, :cpus => size, :bar => "Fork each on semaphore: #{ Misc.fingerprint elems }", :into => Set.new do |elem|
        elems.annotate elem if elems.respond_to? :annotate
        begin
          yield elem
        rescue Interrupt
          Log.warn "Process #{Process.pid} was aborted"
        end
        nil
      end
      nil
    end

    def self.thread_each_on_semaphore(elems, size)
      mutex = Mutex.new
      count = 0
      cv = ConditionVariable.new
      wait_mutex = Mutex.new

      begin

        threads = []
        wait_mutex.synchronize do
          threads = elems.collect do |elem|
            Thread.new(elem) do |elem|

              continue = false
              mutex.synchronize do
                while not continue do
                  if count < size
                    continue = true
                    count += 1
                  end
                  # wait briefly to avoid busy loop; ConditionVariable could be used here properly
                  mutex.sleep 1 unless continue
                end
              end

              begin
                yield elem
              rescue Interrupt
                Log.error "Thread was aborted while processing: #{Misc.fingerprint elem}"
                raise $!
              ensure
                mutex.synchronize do
                  count -= 1
                  cv.signal if mutex.locked?
                end
              end
            end
          end
        end

        threads.each do |thread|
          thread.join
        end
      rescue Exception
        Log.exception $!
        Log.info "Ensuring threads are dead: #{threads.length}"
        threads.each do |thread| thread.kill end
      end
    end
  end
end
