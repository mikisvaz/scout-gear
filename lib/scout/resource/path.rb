module Path
  def open(*args, &block)
    produce
    Open.open(self, *args, &block)
  end

  def read
    produce
    Open.read(self)
  end

  def write(*args, &block)
    Open.write(self.find, *args, &block)
  end
end
