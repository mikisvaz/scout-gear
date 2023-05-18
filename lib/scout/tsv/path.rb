module Path
  def tsv(*args, **kwargs, &block)
    found = self.find
    found = self.set_extension('tsv').find unless found.exists?
    found.produce
    TSV.open(found, *args, **kwargs, &block)
  end

  def index(*args, **kwargs, &block)
    found = self.find
    found = self.set_extension('tsv').find unless found.exists?
    TSV.index(found, *args, **kwargs, &block)
  end
end
