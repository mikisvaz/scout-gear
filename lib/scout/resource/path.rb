module Path
  def open(*args, &block)
    produce
    Open.open(self, *args, &block)
  end

  def read
    produce
    Open.read(self)
  end
end
