class Step
  def self.relocate(path)
    return path if Open.exists?(path)
    Path.setup(path) unless Path === path
    relocated = path.relocate
    return relocated if Open.exists?(relocated)
    subpath = path.split("/")[-3..-1] * "/"
    relocated = Path.setup("var/jobs")[subpath]
    return relocated if Open.exists?(relocated)
    path
  end

  def self.load(path)
    path = relocate(path) unless Open.exists?(path)
    #raise "Could not load #{path}" unless Open.exists?(path)
    s = Step.new path
  end
end
