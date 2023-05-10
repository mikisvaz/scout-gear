require_relative 'parser'
require_relative 'persist/fix_width_table'
module TSV
  def self.index(tsv_file, target: 0, fields: nil, order: true, **kwargs)
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

      dummy_data = TSV.setup({}, :key_field => "Key", :fields => ["Target"])
      if order
        tmp_index = {}
        key_field, field_names = TSV.traverse tsv_file, key_field: target, fields: fields, type: :double, into: dummy_data, unnamed: true, **kwargs do |k,values|
          values.each_with_index do |list,i|
            list.each do |e|
              tmp_index[e] ||= []
              tmp_index[e][i] ||= []
              tmp_index[e][i] << k
            end
          end
        end
        tmp_index.each do |e,list|
          index[e] = list.flatten.compact.uniq.first
        end
      else
        key_field, field_names = TSV.traverse tsv_file, key_field: target, fields: fields, type: :flat, into: dummy_data, unnamed: true, **kwargs do |k,values|
          values.each do |e|
            index[e] = k unless index.include?(e)
          end
        end
      end

      index.key_field = dummy_data.fields * ", "
      index.fields = [dummy_data.key_field]
      index
    end
  end

  def index(*args, **kwargs, &block)
    TSV.index(self, *args, **kwargs, &block)
  end

  def self.range_index(tsv_file, start_field = nil, end_field = nil, key_field: :key, **kwargs)
    persist, type = IndiferentHash.process_options kwargs,
      :persist, :persist_type,
      :persist => false, :persist_type => :fwt
    kwargs.delete :type

    Persist.persist(tsv_file, type, kwargs.merge(:persist => persist, :persist_prefix => "Index")) do |filename|

      max_key_size = 0
      index_data = []
      TSV.traverse tsv_file, key_field: key_field, fields: [start_field, end_field] do |key, values|
        key_size = key.length
        max_key_size = key_size if key_size > max_key_size

        start_pos, end_pos = values
        if Array === start_pos
          start_pos.zip(end_pos).each do |s,e|
            index_data << [key, [s.to_i, e.to_i]]
          end
        else
          index_data << [key, [start_pos.to_i, end_pos.to_i]]
        end
      end

      index = FixWidthTable.get(filename, max_key_size, true)
      index.add_range index_data
      index.read
      index
    end
  end

  def range_index(*args, **kwargs, &block)
    TSV.range_index(self, *args, **kwargs, &block)
  end


  #def range_index(start_field = nil, end_field = nil, options = {})
  #  start_field ||= "Start"
  #  end_field ||= "End"

  #  options = Misc.add_defaults options,
  #    :persist => false, :persist_file => nil, :persist_update => false 

  #  persist_options = Misc.pull_keys options, :persist
  #  persist_options[:prefix] ||= "RangeIndex[#{start_field}-#{end_field}]"

  #  Persist.persist(filename || self.object_id.to_s, :fwt, persist_options) do 
  #    max_key_size = 0
  #    index_data = []
  #    with_unnamed do
  #      with_monitor :desc => "Creating Index Data", :step => 10000 do
  #        through :key, [start_field, end_field] do |key, values|
  #          key_size = key.length
  #          max_key_size = key_size if key_size > max_key_size

  #          start_pos, end_pos = values
  #          if Array === start_pos
  #            start_pos.zip(end_pos).each do |s,e|
  #              index_data << [key, [s.to_i, e.to_i]]
  #            end
  #          else
  #            index_data << [key, [start_pos.to_i, end_pos.to_i]]
  #          end
  #        end
  #      end
  #    end

  #    index = FixWidthTable.get(:memory, max_key_size, true)
  #    index.add_range index_data
  #    index.read
  #    index
  #  end
  #end

  #def self.range_index(file, start_field = nil, end_field = nil, options = {})
  #  start_field ||= "Start"
  #  end_field ||= "End"

  #  data_options = Misc.pull_keys options, :data
  #  filename = case
  #             when (String === file or Path === file)
  #               file
  #             when file.respond_to?(:filename)
  #               file.filename
  #             else
  #               file.object_id.to_s
  #             end
  #  persist_options = Misc.pull_keys options, :persist
  #  persist_options[:prefix] ||= "StaticRangeIndex[#{start_field}-#{end_field}]"

  #  filters = Misc.process_options options, :filters

  #  if filters
  #    filename += ":Filtered[#{filters.collect{|f| f * "="} * ", "}]"
  #  end

  #  Persist.persist(filename, :fwt, persist_options) do
  #    tsv = TSV.open(file, data_options)
  #    if filters
  #      tsv.filter
  #      filters.each do |match, value|
  #        tsv.add_filter match, value
  #      end
  #    end
 
  #    tsv.range_index(start_field, end_field, options)
  #  end
  #end
end
