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
    complete = Path.setup('var/jobs')[path]
    path = complete if ! Open.exists?(path) && complete.find_with_extension('info').exists?
    path = relocate((Path === path ? path : Path.setup(path))) unless Open.exists?(path)
    path = path.find if Path === path
    s = Step.new path
  end

  def to_json(...)
    self.path.to_json
  end
end
