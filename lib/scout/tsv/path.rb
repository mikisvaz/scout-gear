module Path
  def tsv(*args, **kwargs, &block)
    found = produce_and_find('tsv')
    TSV.open(found, *args, **kwargs, &block)
  end

  def index(*args, **kwargs, &block)
    found = produce_and_find('tsv')
    TSV.index(found, *args, **kwargs, &block)
  end
end
