module Path
  def no_method_missing
    class << self
      undef_method :method_missing
    end
  end

  def self.is_filename?(string, need_to_exists = true)
    return false if string.nil?
    return true if Path === string
    return true if String === string and ! string.include?("\n") and string.split("/").select{|p| p.length > 265 }.empty? and (! need_to_exists || File.exist?(string))
    return false
  end

  def self.sanitize_filename(filename, length = 254)
    if filename.length > length
      if filename =~ /(\..{2,9})$/
        extension = $1
      else
        extension = ''
      end

      post_fix = "--#{filename.length}@#{length}_#{Misc.digest(filename)[0..4]}" + extension

      filename = filename[0..(length - post_fix.length - 1)] << post_fix
    else
      filename
    end
    filename
  end

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
    search_paths ||= Path.path_maps
    search_paths = search_paths.dup

    search_paths.keys.collect do |where| 
      found = find(where)
      paths = pattern ? Dir.glob(File.join(found, pattern)) : Dir.glob(found) 

      paths = paths.collect{|p| self.annotate p }

      paths = paths.each do |p|
        p.original = File.join(found.original, p.sub(/^#{found}/, ''))
        p.where = where
      end if found.original and pattern

      paths
    end.flatten.uniq
  end

  def set_extension(extension)
    self.annotate(self + ".#{extension}")
  end

  # Is 'file' newer than 'path'? return non-true if path is newer than file
  def self.newer?(path, file, by_link = false)
    return true if not Open.exists?(file)
    path = path.find if Path === path
    file = file.find if Path === file
    if by_link
      patht = File.exist?(path) ? File.lstat(path).mtime : nil
      filet = File.exist?(file) ? File.lstat(file).mtime : nil
    else
      patht = Open.mtime(path)
      filet = Open.mtime(file)
    end
    return true if patht.nil? || filet.nil?
    diff = patht - filet
    return diff if diff < 0
    return false
  end
end
