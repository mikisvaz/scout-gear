class Step
  def self.relocate(path)
    return path if Open.exists?(path)
    Path.setup(path) unless Path === path
    relocated = path.relocate
    return relocated if Open.exists?(relocated)
    if path.scan("/").length >= 2
      subpath = path.split("/")[-3..-1] * "/"
      relocated = Path.setup("var/jobs")[subpath]
      return relocated if Open.exists?(relocated)
    end
    path
  end

  def self.load(path)
    path = relocate(path) unless Open.exists?(path)
    #raise "Could not load #{path}" unless Open.exists?(path)
    s = Step.new path
  end

  def to_json(...)
    self.path
  end
end
