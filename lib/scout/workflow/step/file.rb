class Step
  def files_dir
    @files_dir ||= begin
                     dir = @path + ".files"
                     if Path === @path
                       @path.annotate(dir)
                     else
                       Path.setup(dir)
                     end
                     dir.pkgdir = self
                     dir
                   end
  end

  def file(file = nil)
    dir = files_dir
    Path.setup(dir) unless Path === dir
    return dir if file.nil?
    dir[file]
  end

  def bundle_files
    [path, info_file, Dir.glob(File.join(files_dir,"**/*"))].flatten.select{|f| Open.exist?(f) }
  end
end
