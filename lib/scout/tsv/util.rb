#require_relative '../../../modules/rbbt-util/lib/rbbt/tsv/manipulate'
#Log.warn "USING OLD RBBT CODE: #{__FILE__}"
module TSV
  #[:each, :collect, :map].each do |method|
  #  define_method(method) do |*args,&block|
  #    super(*args) do |k,v|
  #      NamedArray.setup(v, @fields) unless @unnamed
  #      block.call k, v
  #    end
  #  end
  #end

  #[:select, :reject].each do |method|
  #  define_method(method) do |*args,&block|
  #    res = super(*args) do |k,v|
  #      NamedArray.setup(v, @fields) unless @unnamed
  #      block.call k, v
  #    end
  #    self.annotate(res)
  #    res
  #  end
  #end

end
