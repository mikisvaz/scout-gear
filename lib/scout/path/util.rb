module Path
  def directory?
    return nil unless self.exist?
    File.directory?(self.find)
  end

  def dirname
    self.annotate(File.dirname(self))
  end

  def basename
    self.annotate(File.basename(self))
  end


  def glob(pattern = '*')
    if self.include? "*"
      self.glob_all
    else
      return [] unless self.exist? 
      found = self.find
      exp = File.join(found, pattern)
      paths = Dir.glob(exp).collect{|f| self.annotate(f) }

      paths.each do |p|
        p.original = File.join(found.original, p.sub(/^#{found}/, ''))
      end if found.original

      paths
    end
  end

  def glob_all(pattern = nil, caller_lib = nil, search_paths = nil)
    search_paths ||= Path.search_paths
    search_paths = search_paths.dup

    location_paths = {}
    search_paths.keys.collect do |where| 
      found = find(where, Path.caller_lib_dir, search_paths)
      paths = pattern ? Dir.glob(File.join(found, pattern)) : Dir.glob(found) 

      paths = paths.collect{|p| self.annotate p }

      paths = paths.each do |p|
        p.original = File.join(found.original, p.sub(/^#{found}/, ''))
        p.where = where
      end if found.original and pattern

      location_paths[where] = paths
    end
  end
end
