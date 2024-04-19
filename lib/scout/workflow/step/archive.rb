class Step
  def archived_info
    return {} unless Open.exists?(info_file)
    info[:archived_info] || {}
  end

  def archived_inputs
    return {} unless info[:archived_dependencies]
    archived_info = self.archived_info

    all_inputs = IndiferentHash.setup({})
    deps = info[:archived_dependencies].collect{|p| p.last}
    seen = []
    while path = deps.pop
      dep_info = archived_info[path]
      if Hash === dep_info
        dep_info[:inputs].each do |k,v|
          all_inputs[k] = v unless all_inputs.include?(k)
        end if dep_info[:inputs]
        deps.concat(dep_info[:dependencies].collect{|p| p.last } - seen) if dep_info[:dependencies]
        deps.concat(dep_info[:archived_dependencies].collect{|p| p.last } - seen) if dep_info[:archived_dependencies]
      end
      seen << path
    end

    all_inputs
  end

  def archive_deps(jobs = nil)
    jobs = dependencies if jobs.nil?

    archived_info = jobs.inject({}) do |acc,dep|
      next unless Open.exists?(dep.info_file)
      acc[dep.path] = dep.info
      acc.merge!(dep.archived_info)
      acc
    end

    self.set_info :archived_info, archived_info
    self.set_info :archived_dependencies, info[:dependencies]
  end
end
