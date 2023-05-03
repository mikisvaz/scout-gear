module TSV
  def to_s
    str = ""
    str << "#" << tsv.key_field << "\t" << tsv.fields * "\t" << "\n" if tsv.fields
    tsv.each do |k,v|
      v = v.collect{|_v| v * "|" } if type == :double || type == :flat
      str << k << "\t" << v * "\t" << "\n"
    end
    str
  end
end
