require 'scout'

module Scout

  SENSIBLE_WRITE_DIRS = Open.sensible_write_dir.find_all

  LOCK_DIRS = Path.setup('tmp/tsv_open_locks').find_all +
    Path.setup('tmp/persist_locks').find_all +
    Path.setup('tmp/sensible_write_locks').find_all +
    Path.setup('tmp/produce_locks').find_all +
    Path.setup('tmp/step_info_locks').find_all

  PERSIST_DIRS    = Path.setup('share').find_all  + Path.setup('var/cache/persistence').find_all

  JOB_DIRS = Path.setup('var/jobs').find_all

  MUTEX_FOR_THREAD_EXCLUSIVE = Mutex.new

  def self.dump_memory(file, obj = nil)
    Log.info "Dumping #{obj} objects into #{ file }"
    Thread.new do
      while true
        Open.write(file) do |f|
          MUTEX_FOR_THREAD_EXCLUSIVE.synchronize do
            GC.start
            ObjectSpace.each_object(obj) do |o|
              f.puts "---"
              f.puts(String === o ? o : o.inspect)
            end
          end
        end
        FileUtils.cp file, file + '.save'
        sleep 3
      end
    end
  end

  def self.file_time(file)
    info = {}
    begin
      info[:ctime] = File.ctime file
      info[:atime] = File.atime file
      info[:elapsed] = Time.now - info[:ctime]
    rescue Exception
    end
    info[:ctime] = Time.now - 999
    info
  end

  #{{{ LOCKS

  def self.locks(dirs = LOCK_DIRS)
    dirs.collect do |dir|
      next unless Open.exists? dir
      `find -L "#{ dir }" -name "*.lock" 2>/dev/null`.split "\n"
    end.compact.flatten
  end

  def self.lock_info(dirs = LOCK_DIRS)
    lock_info = {}
    locks(dirs).each do |f|
      lock_info[f] = {}
      begin
        lock_info[f].merge!(file_time(f))
        if File.size(f) > 0
          info = Open.open(f) do |s|
            Open.yaml(s)
          end
          IndiferentHash.setup(info)
          lock_info[f][:pid] = info[:pid]
          lock_info[f][:ppid] = info[:ppid]
        end
      rescue Exception
        Log.warn $!.message
      end
    end
    lock_info
  end

  #{{{ SENSIBLE WRITES

  def self.sensiblewrites(dirs = SENSIBLE_WRITE_DIRS)
    dirs.collect do |dir|
      next unless Open.exists? dir
      `find -L "#{ dir }" -not -name "*.lock" -not -type d 2>/dev/null`.split "\n"
    end.compact.flatten
  end

  def self.sensiblewrite_info(dirs = SENSIBLE_WRITE_DIRS)
    info = {}
    sensiblewrites(dirs).each do |f|
      begin
        i = file_time(f)
        info[f] = i
      rescue
        Log.exception $!
      end
    end
    info
  end

  # PERSISTS

  def self.persists(dirs = PERSIST_DIRS)
    dirs.collect do |dir|
      next unless Open.exists? dir
      `find -L "#{ dir }" -name "*.persist" 2>/dev/null`.split "\n"
    end.compact.flatten
  end

  def self.persist_info(dirs = PERSIST_DIRS)
    info = {}
    persists(dirs).each do |f|
      begin
        i = file_time(f)
        info[f] = i
      rescue
        Log.exception $!
      end
    end
    info
  end

  # PERSISTS

  def self.job_info(workflows = nil, tasks = nil, dirs = JOB_DIRS)
    require 'rbbt/workflow/step'

    workflows = [workflows] if workflows and not Array === workflows
    workflows = workflows.collect{|w| w.to_s} if workflows

    tasks = [tasks] if tasks and not Array === tasks
    tasks = tasks.collect{|w| w.to_s} if tasks

    jobs = {}
    seen = Set.new
    _files = Set.new
    dirs.collect do |dir|
      next unless Open.exists? dir

      task_dir_workflows = {}
      tasks_dirs = if dir == '.'
                    ["."]
                   else
                     #workflowdirs = if (dir_sub_path = Open.find_repo_dir(workflowdir))
                     #                 repo_dir, sub_path = dir_sub_path
                     #                 Open.list_repo_files(*dir_sub_path).collect{|f| f.split("/").first}.uniq.collect{|f| File.join(repo_dir, f)}.uniq
                     #               else
                     #                 dir.glob("*")
                     #               end

                     workflowdirs = dir.glob("*")

                     workflowdirs.collect do |workflowdir|
                       workflow = File.basename(workflowdir)
                       next if workflows and not workflows.include? workflow

                       #task_dirs = if (dir_sub_path = Open.find_repo_dir(workflowdir))
                       #              repo_dir, sub_path = dir_sub_path
                       #              Open.list_repo_files(*dir_sub_path).collect{|f| f.split("/").first}.uniq.collect{|f| File.join(repo_dir, f)}.uniq
                       #            else
                       #              workflowdir.glob("*")
                       #            end

                       task_dirs = workflowdir.glob("*")

                       task_dirs.each do |tasks_dir|
                         task_dir_workflows[tasks_dir] = workflow
                       end
                     end.compact.flatten
                   end

      tasks_dirs.collect do |taskdir|
        task = File.basename(taskdir)
        next if tasks and not tasks.include? task


        #files = if (dir_sub_path = Open.find_repo_dir(taskdir))
        #          repo_dir, sub_path = dir_sub_path
        #          Open.list_repo_files(*dir_sub_path).reject do |f|
        #            f.include?("/.info/") ||
        #              f.include?(".files/") ||
        #              f.include?(".pid/") ||
        #              File.directory?(f)
        #          end.collect do |f|
        #            File.join(repo_dir, f)
        #          end
        #        else
        #          #cmd = "find -L '#{ taskdir }/'  -not \\( -path \"#{taskdir}/*.files/*\" -prune \\) -not -name '*.pid' -not -name '*.notify' -not -name '\\.*' 2>/dev/null"
        #          cmd = "find -L '#{ taskdir }/' -not \\( -path \"#{taskdir}/.info/*\" -prune \\) -not \\( -path \"#{taskdir}/*.files/*\" -prune \\) -not -name '*.pid' -not -name '*.md5' -not -name '*.notify' -not -name '\\.*' \\( -not -type d -o -name '*.files' \\)  2>/dev/null"

        #          CMD.cmd(cmd, :pipe => true).read.split("\n")
        #        end

        files = begin
                  cmd = "find -L '#{ taskdir }/' -not \\( -path \"#{taskdir}/.info/*\" -prune \\) -not \\( -path \"#{taskdir}/*.files/*\" -prune \\) -not -name '*.pid' -not -name '*.md5' -not -name '*.notify' -not -name '\\.*' \\( -not -type d -o -name '*.files' \\)  2>/dev/null"

                  CMD.cmd(cmd, :pipe => true).read.split("\n")
                end

        files = files.sort_by{|f| Open.mtime(f) || Time.now}
        workflow = task_dir_workflows[taskdir]
        TSV.traverse files, :type => :array, :into => jobs, :_bar => "Finding jobs in #{ taskdir }" do |file|
          _files << file
          if m = file.match(/(.*)\.(info|pid|files)$/)
            file = m[1]
          end
          next if seen.include? file
          seen << file

          name = file[taskdir.length+1..-1]
          info_file = file + '.info'

          info = {}

          info[:workflow] = workflow
          info[:task] = task
          info[:name] = name

          if Open.exists? file
            info = info.merge(file_time(file))
            info[:done] = true
            info[:info_file] = Open.exist?(info_file) ? info_file : nil
          else
            info = info.merge({:info_file => info_file, :done => false})
          end

          [file, info]
        end

      end.compact.flatten
    end.compact.flatten
    jobs
  end

  # REST

  def self.__jobs(dirs = JOB_DIRS)
    job_files = {}
    dirs.each do |dir|
      workflow_dirs = dir.glob("*").each do |wdir|
        workflow = File.basename(wdir)
        job_files[workflow] = {}
        task_dirs = wdir.glob('*')
        task_dirs.each do |tdir|
          task = File.basename(tdir)
          job_files[workflow][task] = tdir.glob('*')
        end
      end
    end
    jobs = {}
    job_files.each do |workflow,task_jobs|
      jobs[workflow] ||= {}
      task_jobs.each do |task, files|
        jobs[workflow][task] ||= {}
        files.each do |f|
          next if f =~ /\.lock$/
          job = f.sub(/\.(info|files)/,'')

          jobs[workflow][task][job] ||= {}
          if jobs[workflow][task][job][:status].nil?
            status = nil
            status = :done if Open.exists? job
            if status.nil? and f=~/\.info/
              info = begin
                       Step::INFO_SERIALIZER.load(Open.read(f, :mode => 'rb'))
                     rescue
                       {}
                     end
              status = info[:status]
              pid = info[:pid]
            end

            jobs[workflow][task][job][:pid] = pid if pid
            jobs[workflow][task][job][:status] = status if status
          end
        end
      end
    end
    jobs
  end

  def self.load_lock(lock)
    begin
      info = Misc.insist 3 do
        Open.yaml(lock)
      end
      info.values_at "pid", "ppid", "time"
    rescue Exception
      time = begin
               File.atime(lock)
             rescue Exception
               Time.now
             end
      [nil, nil, time]
    end
  end

end
