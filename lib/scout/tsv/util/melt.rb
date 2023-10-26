module TSV
  def melt_columns(value_field, column_field)
    target = TSV.setup({}, :key_field => "ID", :fields => [key_field, value_field, column_field], :type => :list, :cast => cast)
    each do |k,values|
      i = 0
      values.zip(fields).each do |v,f|
        target["#{k}:#{i}"] = [k,v,f]
        i+=1
      end
    end
    target
  end
end
