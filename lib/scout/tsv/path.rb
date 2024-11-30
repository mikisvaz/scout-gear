module Path
  def tsv(*args, **kwargs, &block)
    found = produce_and_find('tsv')
    TSV.open(found, *args, **kwargs, &block)
  end

  def tsv_options(options = {})
    self.open do |stream|
      TSV::Parser.new(stream, **options).options
    end
  end

  def index(*args, **kwargs, &block)
    found = produce_and_find('tsv')
    TSV.index(found, *args, **kwargs, &block)
  end

  def identifier_file_path
    if self.dirname.identifiers.exists?
      self.dirname.identifiers
    else
      nil
    end
  end
end
