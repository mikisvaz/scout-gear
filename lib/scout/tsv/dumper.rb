module TSV
  def to_s
    str = ""
    str << "#" << self.key_field << "\t" << self.fields * "\t" << "\n" if self.fields
    self.each do |k,v|
      v = v.collect{|_v| v * "|" } if self.type == :double || self.type == :flat
      str << k << "\t" << v * "\t" << "\n"
    end
    str
  end
end
