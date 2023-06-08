class Step
  def files_dir
    @files_dir ||= begin
                     dir = @path + ".files"
                     @path.annotate(dir) if Path === @path
                     dir.pkgdir = self
                     dir
                   end
  end

  def file(file)
    dir = files_dir
    Path.setup(dir) unless Path === dir
    dir[file]
  end

  def bundle_files
    [path, info_file, Dir.glob(File.join(files_dir,"**/*"))].flatten.select{|f| Open.exist?(f) }
  end
end
