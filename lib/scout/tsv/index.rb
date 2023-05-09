require_relative 'parser'
module TSV
  def self.index(tsv_file, target: 0, order: true, **kwargs)
    persist, type = IndiferentHash.process_options kwargs,
      :persist, :persist_type,
      :persist => false, :persist_type => "HDB"
    kwargs.delete :type

    Persist.persist(tsv_file, type, kwargs.merge(:persist => persist, :persist_prefix => "Index")) do |filename|
      if filename
        index = ScoutCabinet.open(filename, true, type)
        TSV.setup(index, :type => :single)
        index.extend TSVAdapter 
      else
        index = TSV.setup({}, :type => :single)
      end

      dummy_data = nil
      if order
        tmp_index = {}
        dummy_data = Open.open(tsv_file) do |file|
          TSV.parse file, key_field: target, type: :double, **kwargs do |k,values|
            values.each_with_index do |list,i|
              list.each do |e|
                tmp_index[e] ||= []
                tmp_index[e][i] ||= []
                tmp_index[e][i] << k
              end
            end
          end
        end
        tmp_index.each do |e,list|
          index[e] = list.flatten.compact.uniq.first
        end
      else
        dummy_data = Open.open(tsv_file) do |file|
          TSV.parse file, key_field: target, type: :flat, **kwargs do |k,values|
            values.each do |e|
              index[e] = k unless index.include?(e)
            end
          end
        end
      end
      index.key_field = dummy_data.fields * ", "
      index.fields = [dummy_data.key_field]
      index
    end
  end
end
