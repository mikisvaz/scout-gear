class Step
  def progress_bar(msg = "Progress", options = nil, &block)
    if Hash === msg and options.nil?
      options = msg
      msg = nil
    end
    options = {} if options.nil?

    max = options[:max]
    Open.mkdir files_dir
    bar = Log::ProgressBar.new_bar(max, {:desc => msg, :file => (@exec ? nil : file(:progress))}.merge(options))

    if block_given?
      bar.init
      res = yield bar
      bar.remove
      res
    else
      bar
    end
  end
end

