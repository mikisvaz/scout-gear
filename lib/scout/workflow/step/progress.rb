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

  def traverse(obj, desc: nil , **kwargs, &block)
    desc = "Processing #{self.short_path}" if desc.nil?
    kwargs[:bar] = self.progress_bar(desc) unless kwargs.include?(:bar)
    TSV.traverse obj, **kwargs, &block
  end

  def monitor_stream(stream, options = {}, &block)
    case options[:bar] 
    when TrueClass
      bar = progress_bar 
    when Hash
      bar = progress_bar options[:bar]
    when Numeric
      bar = progress_bar :max => options[:bar]
    else
      bar = options[:bar]
    end

    out = if bar.nil?
            Open.line_monitor_stream stream, &block
          elsif (block.nil? || block.arity == 0)
            Open.line_monitor_stream stream do
              bar.tick
            end
          elsif block.arity == 1
            Open.line_monitor_stream stream do |line|
              bar.tick
              block.call line
            end
          elsif block.arity == 2
            Open.line_monitor_stream stream do |line|
              block.call line, bar
            end
          end

    if bar
      ConcurrentStream.setup(out, :abort_callback => Proc.new{
        bar.done
        Log::ProgressBar.remove_bar(bar, true)
      }, :callback => Proc.new{
        bar.done
        Log::ProgressBar.remove_bar(bar)
      })
    end

    bgzip = (options[:compress] || options[:gzip]).to_s == 'bgzip'
    bgzip = true if options[:bgzip]

    gzip = true if options[:compress] || options[:gzip]
    if bgzip
      Open.bgzip(out)
    elsif gzip
      Open.gzip(out)
    else
      out
    end
  end
end

