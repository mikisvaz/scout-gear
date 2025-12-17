module Path
  def self.step_file?(path)
    return false unless path =~ /\.files(?:\/|$)/
    parts = path.split("/")
    job = parts.select{|p| p =~ /\.files$/}.first

    if job
      i = parts.index job
      begin
        workflow, task = parts.values_at i - 2, i - 1
        _loaded = false
        begin
          Kernel.const_get(workflow)
        rescue
          if ! _loaded
            Workflow.require_workflow workflow
            _loaded = true
            retry
          end
          raise $!
        end
        return parts[i-2..-1] * "/"
      rescue
        Log.exception $!
      end
    end

    false
  end

  alias original_digest_str digest_str

  def digest_str
    if step_file = Path.step_file?(self)
      "Step file: #{step_file}"
    else
      original_digest_str
    end
  end
end
