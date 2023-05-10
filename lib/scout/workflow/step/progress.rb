class Step
  def progress_bar(msg = "Progress", options = nil)
    if Hash === msg and options.nil?
      options = msg
      msg = nil
    end
    options = {} if options.nil?

    max = options[:max]
    Open.mkdir files_dir
    Log::ProgressBar.new_bar(max, {:desc => msg, :file => (@exec ? nil : file(:progress))}.merge(options))
  end
end

