require_relative 'parser'
require_relative 'transformer'
require_relative '../persist/tsv'
module TSV

  def self.select_prefix_str(select)
    str = begin
            case select
            when nil
              nil
            when Array
              case select.first
              when nil
                nil
              when Array
                select.collect{|p| p * "="}*","
              else
                select.collect{|p| p.to_s }*"="
              end
            when Hash
              if select.empty?
                nil
              else
                select.collect do |key,value|
                  [key.to_s, value.to_s] * "="
                end * ","
              end
            end
          rescue
            Log.warn "Error in select_prefix_str: #{Log.fingerprint(select)}: #{$!.message}"
            str = nil
          end
    if str.nil?
      ""
    else
      "[select:#{str}]"
    end
  end

  def self.index(tsv_file, target: :key, fields: nil, order: true, bar: nil, **kwargs)
    kwargs = IndiferentHash.add_defaults kwargs, unnamed: true
    engine = IndiferentHash.process_options kwargs, :engine

    fields = :all if fields.nil?

    prefix = case fields
             when :all
               "Index[#{target}]"
             else
               "Index[#{Array === fields ? fields * "," : fields}->#{target}]"
             end

    prefix += select_prefix_str(kwargs[:select])

    persist_options = IndiferentHash.pull_keys kwargs, :persist
    persist_options = IndiferentHash.add_defaults persist_options, :prefix => prefix, :engine => :HDB, :persist => false

    data_options = IndiferentHash.pull_keys kwargs, :data

    Persist.persist(tsv_file, persist_options[:engine], persist_options.merge(other_options: kwargs.merge(target: target, fields: fields, order: order, data_options: data_options))) do |filename|
      if filename
        index = ScoutCabinet.open(filename, true, engine)
        TSV.setup(index, :type => :single)
        index.extend TSVAdapter
      else
        index = TSV.setup({}, :type => :single)
      end

      log_msg = "Index #{Log.fingerprint tsv_file} target #{Log.fingerprint target}"
      Log.low log_msg
      bar = log_msg if TrueClass === bar

      if order
        tmp_index = {}
        include_self = fields == :all || (Array === fields) && fields.include?(target)
        target_key_field, source_field_names = Open.traverse tsv_file, type: :double, key_field: target, fields: fields, bar: bar, **kwargs do |k,values|
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
      end

      index.key_field = source_field_names * ","
      index.fields = [target_key_field]

      index
    end
  end

  def index(*args, **kwargs, &block)
    TSV.index(self, *args, **kwargs, &block)
 end

  def self.range_index(tsv_file, start_field = nil, end_field = nil, key_field: :key, bar: nil, **kwargs)
    kwargs = IndiferentHash.add_defaults kwargs, unnamed: true
    type, data_persist = IndiferentHash.process_options kwargs, :type, :data_persist

    prefix = "RangeIndex[#{start_field}-#{end_field}]"

    prefix += select_prefix_str(kwargs[:select])

    persist_options = IndiferentHash.pull_keys kwargs, :persist
    persist_options = IndiferentHash.add_defaults persist_options, :prefix => prefix, :type => :fwt, :persist => true

    data_options = IndiferentHash.pull_keys kwargs, :data

    Persist.persist(tsv_file, persist_options[:type], persist_options.merge(other_options: kwargs.merge(start_field: start_field, end_field: end_field, key_field: key_field))) do |filename|
      tsv_file = TSV.open(tsv_file, *data_options) if data_options[:persist] && ! TSV === tsv_file

      log_msg = "RangeIndex #{Log.fingerprint tsv_file} #{[start_field, end_field]*"-"}"
      Log.low log_msg
      bar = log_msg if TrueClass === bar

      max_key_size = 0
      index_data = []
      TSV.traverse tsv_file, key_field: key_field, fields: [start_field, end_field], bar: bar, unnamed: true, **kwargs do |key, values|
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
    kwargs = IndiferentHash.add_defaults kwargs, unnamed: true
    type, data_persist = IndiferentHash.process_options kwargs, :type

    prefix = "PositionIndex[#{pos_field}]"

    prefix += select_prefix_str(kwargs[:select])

    persist_options = IndiferentHash.pull_keys kwargs, :persist
    persist_options = IndiferentHash.add_defaults persist_options, :prefix => prefix, :type => :fwt, :persist => true

    data_options = IndiferentHash.pull_keys kwargs, :data

    Persist.persist(tsv_file, persist_options[:type], persist_options.merge(other_options: kwargs.merge(pos_field: pos_field, key_field: key_field))) do |filename|
      tsv_file = TSV.open(tsv_file, *data_options) if data_options[:persist] && ! TSV === tsv_file

      log_msg = "PositionIndex #{Log.fingerprint tsv_file} #{pos_field}"
      Log.low log_msg
      bar = log_msg if TrueClass === bar

      max_key_size = 0
      index_data = []
      TSV.traverse tsv_file, key_field: key_field, fields: [pos_field], type: :flat, cast: :to_i, bar: bar, **kwargs do |key, pos|
        key_size = key.length
        max_key_size = key_size if key_size > max_key_size

        if Array === pos
          pos.each do |p|
            index_data << [key, p]
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
