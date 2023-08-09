require_relative 'parser'
require_relative 'transformer'
require_relative 'persist/fix_width_table'
module TSV
  def self.index(tsv_file, target: :key, fields: nil, order: true, bar: nil, **kwargs)
    persist, type, persist_update, data_persist = IndiferentHash.process_options kwargs,
      :persist, :persist_type, :persist_update, :data_persist,
      :persist => false, :persist_type => "HDB"
    kwargs.delete :type

    fields = :all if fields.nil?

    Persist.persist(tsv_file, type, kwargs.merge(target: target, fields: fields, persist: persist, update: persist_update, prefix: "Index", other_options: {fields: fields, target: target, order: order})) do |filename|
      if filename
        index = ScoutCabinet.open(filename, true, type)
        TSV.setup(index, :type => :single)
        index.extend TSVAdapter 
      else
        index = TSV.setup({}, :type => :single)
      end

      tsv_file = TSV.open(tsv_file, persist: true) if data_persist && ! TSV === tsv_file

      log_msg = "Index #{Log.fingerprint tsv_file} target #{Log.fingerprint target}"
      Log.low log_msg
      bar = log_msg if TrueClass === bar

      if order
        tmp_index = {}
        include_self = fields == :all || (Array === fields) && fields.include?(target)
        target_key_field, source_field_names = Open.traverse tsv_file, type: :double, key_field: target, fields: fields, unnamed: true, bar: bar, **kwargs do |k,values|
          tmp_index[k] ||= [[k]] if include_self
          values.each_with_index do |list,i|
            i += 1 if include_self
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

        index.key_field = source_field_names * ","
        index.fields = [target_key_field]

        tmp_index = {}

      else
        target_key_field, source_field_names =  Open.traverse tsv_file, key_field: target, fields: fields, type: :flat, unnamed: true, bar: bar, **kwargs do |k,values|
          values.each do |e|
            index[e] = k unless index.include?(e)
          end
        end

        index.key_field = source_field_names * ","
        index.fields = [target_key_field]
      end


      index
    end
  end

  def index(*args, **kwargs, &block)
    TSV.index(self, *args, **kwargs, &block)
  end

  def self.range_index(tsv_file, start_field = nil, end_field = nil, key_field: :key, bar: nil, **kwargs)
    persist, type, persist_update, data_persist = IndiferentHash.process_options kwargs,
      :persist, :persist_type, :persist_update, :data_persist,
      :persist => false, :persist_type => :fwt
    kwargs.delete :type
    kwargs[:unnamed] = true

    Persist.persist(tsv_file, type, 
                    :persist => persist, :prefix => "RangeIndex[#{[start_field, end_field]*"-"}]", update: persist_update,
                    :other_options => kwargs) do |filename|

      tsv_file = TSV.open(tsv_file, persist: true) if data_persist && ! TSV === tsv_file

      log_msg = "RangeIndex #{Log.fingerprint tsv_file} #{[start_field, end_field]*"-"}"
      Log.low log_msg
      bar = log_msg if TrueClass === bar

      max_key_size = 0
      index_data = []
      TSV.traverse tsv_file, key_field: key_field, fields: [start_field, end_field], bar: bar, **kwargs do |key, values|
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

      filename = :memory if filename.nil?
      index = FixWidthTable.get(filename, max_key_size, true)
      index.add_range index_data
      index.read
      index
    end
  end

  def self.pos_index(tsv_file, pos_field = nil, key_field: :key, bar: nil, **kwargs)
    persist, type, persist_update, data_persist = IndiferentHash.process_options kwargs,
      :persist, :persist_type, :persist_update, :data_persist,
      :persist => false, :persist_type => :fwt
    kwargs.delete :type
    kwargs[:unnamed] = true

    Persist.persist(tsv_file, type, 
                    :persist => persist, :prefix => "RangeIndex[#{pos_field}]", update: persist_update,
                    :other_options => kwargs) do |filename|

      tsv_file = TSV.open(tsv_file, persist: true) if data_persist && ! TSV === tsv_file

      log_msg = "RangeIndex #{Log.fingerprint tsv_file} #{pos_field}"
      Log.low log_msg
      bar = log_msg if TrueClass === bar

      max_key_size = 0
      index_data = []
      TSV.traverse tsv_file, key_field: key_field, fields: [pos_field], type: :single, cast: :to_i, bar: bar, **kwargs do |key, pos|
        key_size = key.length
        max_key_size = key_size if key_size > max_key_size

        if Array === pos
          pos.zip(end_pos).each do |p|
            index_pos << [key, p]
          end
        else
          index_data << [key, pos]
        end
      end

      filename = :memory if filename.nil?
      index = FixWidthTable.get(filename, max_key_size, false)
      index.add_point index_data
      index.read
      index
    end
  end

  def range_index(*args, **kwargs, &block)
    TSV.range_index(self, *args, **kwargs, &block)
  end

  def pos_index(*args, **kwargs, &block)
    TSV.pos_index(self, *args, **kwargs, &block)
  end
end
