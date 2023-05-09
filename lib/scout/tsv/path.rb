module Path
  def tsv(...)
    found = self.find
    found = self.set_extension('tsv').find unless found.exists?
    TSV.open(found, ...)
  end

  def index(...)
    found = self.find
    found = self.set_extension('tsv').find unless found.exists?
    TSV.index(found, ...)
  end
end
