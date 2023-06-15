class SSHLine
  def self.locate(server, paths, map: :user)
    SSHLine.scout server, <<-EOF
map = :#{map}
paths = [#{paths.collect{|p| "'" + p + "'" } * ", " }]
located = paths.collect{|p| Path.setup(p).find(map) }
identified = paths.collect{|p| Resource.identify(p) }
[located, identified]
    EOF
  end

  def self.rsync(source_path, target_path, directory: false, source: nil, target: nil, dry_run: false, hard_link: false)
    rsync_args = "-avztHP --copy-unsafe-links --omit-dir-times "

    rsync_args << "--link-dest '#{source_path}' " if hard_link && ! source

    source_path = source_path + "/" if directory && ! source_path.end_with?("/")
    target_path = target_path + "/" if directory && ! target_path.end_with?("/")
    if target
      SSHLine.mkdir target, File.dirname(target_path)
    else
      Open.mkdir(File.dirname(target_path))
    end

    cmd = 'rsync '
    cmd << rsync_args
    cmd << '-nv ' if dry_run
    cmd << (source ? [source, source_path] * ":" : source_path) << " "
    cmd << (target ? [target, target_path] * ":" : target_path) << " "

    CMD.cmd_log(cmd, :log => Log::HIGH)
  end

  def self.sync(paths, source: nil, target: nil, map: :user, **kwargs)
    source = nil if source == 'localhost'
    target = nil if target == 'localhost'

    if source
      source_paths, identified_paths = SSHLine.locate(source, paths)
    else
      source_paths = paths.collect{|p| Path === p ? p.find : p }
      identified_paths = paths.collect{|p| Resource.identify(p) }
    end

    if target
      target_paths = SSHLine.locate(target, identified_paths, map: map)
    else
      target_paths = identified_paths.collect{|p| p.find(map) }
    end

    source_paths.zip(target_paths).each do |source_path,target_path|
      rsync(source_path, target_path, source: source, target: target, **kwargs)
    end
  end
end
