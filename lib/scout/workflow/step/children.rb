class Step
  def child(&block)
    child_pid = Process.fork &block
    children_pids = info[:children_pids]
    if children_pids.nil?
      children_pids = [child_pid]
    else
      children_pids << child_pid
    end
    set_info :children_pids, children_pids
    child_pid
  end

  def cmd(*args)
    all_args = *args

    all_args << {} unless Hash === all_args.last

    level = all_args.last[:log] || 0
    level = 0 if TrueClass === level
    level = 10 if FalseClass === level
    level = level.to_i

    all_args.last[:log] = true
    all_args.last[:pipe] = true

    io = CMD.cmd(*all_args)
    child_pid = io.pids.first

    children_pids = info[:children_pids]
    if children_pids.nil?
      children_pids = [child_pid]
    else
      children_pids << child_pid
    end
    set_info :children_pids, children_pids

    while c = io.getc
      STDERR << c if Log.severity <= level
      if c == "\n"
        Log.logn "STDOUT [#{child_pid}]: ", level
      end
    end

    io.join

    nil
  end

end

