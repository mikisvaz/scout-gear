module TSV
  def reorder(key_field = nil, fields = nil, merge: true, one2one: true) 
    res = self.annotate({})
    key_field_name, field_names = traverse key_field, fields, one2one: one2one do |k,v|
      if @type == :double && merge && res.include?(k)
        current = res[k]
        if merge == :concat
          v.each_with_index do |new,i|
            next if new.empty?
            current[i].concat(new)
          end
        else
          merged = []
          v.each_with_index do |new,i|
            next if new.empty?
            merged[i] = current[i] + new
          end
          res[k] = merged
        end
      else
        res[k] = v
      end
    end
    res.key_field = key_field_name
    res.fields = field_names
    res
  end

  def slice(fields)
    reorder :key, fields
  end
end
