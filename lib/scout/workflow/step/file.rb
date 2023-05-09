class Step
  def files_dir
    @files_dir ||= begin
                     dir = @path + ".files"
                     @path.annotate(dir) if Path === @path
                     dir
                   end
  end

  def file(file)
    dir = files_dir
    Path.setup(dir) unless Path === dir
    dir[file]
  end
end
