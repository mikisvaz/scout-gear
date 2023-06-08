module Resource
  def identify(path)
    return path unless path.start_with?("/")
    path_maps = path.path_maps if Path === path
    path_maps ||= self.path_maps || Path.path_maps
    path = File.expand_path(path)
    path += "/" if File.directory?(path)

    map_order ||= (path_maps.keys & Path.basic_map_order) + (path_maps.keys - Path.basic_map_order)
    map_order -= [:current, "current"]

    choices = []
    map_order.uniq.each do |name|
      pattern = path_maps[name]
      pattern = path_maps[pattern] while Symbol === pattern
      next if pattern.nil?

      pattern = pattern.sub('{PWD}', Dir.pwd)
      pattern = pattern.sub('{HOME}', ENV["HOME"])
      if String ===  pattern and pattern.include?('{')
        regexp = "^" + pattern
          .gsub(/{(TOPLEVEL)}/,'(?<\1>[^/]+)')
          .gsub(/{([^}]+)}/,'(?<\1>[^/]+)?') +
        "(?:/(?<REST>.*))?/?$"
        if m = path.match(regexp) 
          if ! m.named_captures.include?("PKGDIR") || m["PKGDIR"] == self.pkgdir
            unlocated = %w(TOPLEVEL SUBPATH PATH REST).collect{|c| 
              m.named_captures.include?(c) ? m[c] : nil
            }.compact * "/"
            unlocated.gsub!(/\/+/,'/')
            unlocated[self.subdir] = "" if self.subdir
            choices << self.annotate(unlocated)
          end
        end
      end
    end

    identified = choices.sort_by{|s| s.length }.first

    Path.setup(identified || path, self, nil, path_maps)
  end

  def self.identify(path)
    resource = path.pkgdir if Path === path
    resource = Scout unless Resource === resource
    unlocated = resource.identify path
  end

  def self.relocate(path)
    return path if Open.exists?(path)
    unlocated = identify(path)
    unlocated.find
  end
end

