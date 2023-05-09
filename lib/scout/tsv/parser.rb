require_relative '../named_array'
module TSV
  def self.cast_value(value, cast)
    if Array === value
      value.collect{|e| cast_value(e, cast) }
    else
      value.send(cast)
    end
  end

  def self.parse_line(line, type: :list, key: 0, positions: nil, sep: "\t", sep2: "|", cast: nil)
    items = line.split(sep, -1)

    if positions.nil? && key == 0
      key = items.shift
    elsif positions.nil? 
      key = items.delete_at(key)
      key = key.split(sep2) if type == :double
    else 
      key, items = items[key], items.values_at(*positions)
      key = key.split(sep2) if type == :double
    end

    items = case type
            when :list
              items
            when :single
              items.first
            when :flat
              [items]
            when :double
              items.collect{|i| i.split(sep2, -1) }
            end


    if cast
      items = cast_value(items, cast)
    end

    [key, items]
  end

  def self.parse_stream(stream, data: nil, source_type: nil, type: :list, merge: true, one2one: false, fix: true, bar: false, first_line: nil, **kargs, &block)
    begin
      bar = Log::ProgressBar.new_bar(bar) if bar

      source_type = type if source_type.nil?

      data = {} if data.nil?
      merge = false if type != :double
      line = first_line || stream.gets
      while line
        begin
          line.strip!
          line = Misc.fixutf8(line) if fix
          bar.tick if bar
          key, items = parse_line(line, type: source_type, **kargs)

          if Array === key
            keys = key
            if one2one
              key_items = keys.length.times.collect{|i| items.collect{|list| [list[i] || list[0]] } }
            else
              key_items = false
            end
          else
            keys = [key]
            key_items = false
          end

          keys.each_with_index do |key,i|
            if key_items
              these_items = key_items[i]
            else
              these_items = items
            end

            these_items = case [source_type, type]
                          when [:single, :single]
                            these_items
                          when [:list, :single]
                            these_items.first
                          when [:flat, :single]
                            these_items.first
                          when [:double, :single]
                            these_items.first.first
                          when [:single, :list]
                            [these_items]
                          when [:list, :list]
                            these_items
                          when [:flat, :list]
                            these_items
                          when [:double, :list]
                            these_items.collect{|l| l.first }
                          when [:single, :flat]
                            [these_items]
                          when [:list, :flat]
                            these_items
                          when [:flat, :flat]
                            these_items
                          when [:double, :flat]
                            these_items.flatten
                          when [:single, :double]
                            [[these_items]]
                          when [:list, :double]
                            these_items.collect{|l| [l] }
                          when [:flat, :double]
                            [these_items]
                          when [:double, :double]
                            these_items
                          end

            if block_given?
              res = block.call(key, these_items)
              data[key] = res unless res.nil? || FalseClass === data
              next
            end

            if ! merge || ! data.include?(key)
              data[key] = these_items
            else
              current = data[key]
              if merge == :concat
                these_items.each_with_index do |new,i|
                  next if new.empty?
                  current[i].concat(new)
                end
              else
                merged = []
                these_items.each_with_index do |new,i|
                  next if new.empty?
                  merged[i] = current[i] + new
                end
                data[key] = merged
              end
            end
          end
        ensure
          line = stream.gets
        end
      end
      data
    ensure
      Log::ProgressBar.remove_bar(bar) if bar
    end
  end

  def self.parse_header(stream, fix: true, header_hash: '#', sep: "\t")
    raise "Closed stream" if IO === stream && stream.closed?

    options = {}
    preamble = []

    # Get line

    #Thread.pass while IO.select([stream], nil, nil, 1).nil? if IO === stream
    line = stream.gets
    return {} if line.nil?
    line = Misc.fixutf8 line.chomp if fix

    # Process options line
    if line and (String === header_hash && m = line.match(/^#{header_hash}: (.*)/))
      options = IndiferentHash.string2hash m.captures.first.chomp
      line = stream.gets
      line = Misc.fixutf8 line.chomp if line && fix
    end

    # Determine separator
    sep = options[:sep] if options[:sep]

    # Process fields line
    preamble << line if line
    while line && (TrueClass === header_hash || (String === header_hash && line.start_with?(header_hash)))
      fields = line.split(sep, -1)
      key_field = fields.shift
      key_field = key_field.sub(header_hash, '') if String === header_hash && ! header_hash.empty?

      line = (header_hash != "" ?  stream.gets : nil)
      line = Misc.fixutf8 line.chomp if line
      preamble << line if line
      break if TrueClass === header_hash || header_hash == ""
    end

    preamble = preamble[0..-3] * "\n"

    line ||= stream.gets

    first_line = line

    [options, key_field, fields, first_line, preamble]
  end

  KEY_PARAMETERS = begin
                     params = []
                     (method(:parse_line).parameters + method(:parse_stream).parameters).each do |type, name|
                       params << name if type == :key
                     end
                     params
                   end

  class Parser
    attr_accessor :stream, :options, :key_field, :fields, :first_line, :preamble
    def initialize(file, fix: true, header_hash: "#", sep: "\t")
      if IO === file
        @stream = file
      else
        @stream = Open.open(file)
      end
      @options, @key_field, @fields, @first_line, @preamble = TSV.parse_header(@stream, fix:fix, header_hash:header_hash, sep:sep)
      @options[:sep] = sep if @options[:sep].nil?
    end

    def all_fields
      [@key_field] + @fields
    end

    def traverse(key_field: nil, fields: nil, filename: nil, namespace: nil,  **kwargs, &block)
      if fields
        all_field_names ||= [@key_field] + @fields
        positions = NamedArray.identify_name(all_field_names, fields)
        kwargs[:positions] = positions
        field_names = all_field_names.values_at *positions
      else
        field_names = @fields
      end

      if key_field
        all_field_names ||= [@key_field] + @fields
        key = NamedArray.identify_name(all_field_names, key_field)
        kwargs[:key] = key
        key_field_name = all_field_names[key]
        if fields.nil?
          field_names = all_field_names - [@key_field]
        end
      else
        key_field_name = @key_field
      end

      @options.each do |option,value|
        option = option.to_sym
        next unless KEY_PARAMETERS.include? option
        kwargs[option] = value unless kwargs.include?(option)
      end

      kwargs[:source_type] = @options[:type]
      kwargs[:data] = false if kwargs[:data].nil?

      data = TSV.parse_stream(@stream, first_line: @first_line, **kwargs, &block)

      TSV.setup(data, :key_field => key_field_name, :fields => field_names, :type => @type) if data

      data || self
    end

  end

  def self.parse(stream, fix: true, header_hash: "#", sep: "\t", filename: nil, namespace: nil,  **kwargs, &block)
    parser = TSV::Parser.new stream, fix: fix, header_hash: header_hash, sep: sep
    kwargs = parser.options.merge(kwargs)

    type = kwargs[:type] ||= :double
    if (data = kwargs[:data]) && data.respond_to?(:persistence_class)
      TSV.setup(data, type: type)
      data.extend TSVAdapter
    end

    kwargs[:data] = {} if kwargs[:data].nil?

    data = parser.traverse **kwargs, &block
    data.type = type
    data.filename = filename
    data.namespace = namespace
    data
  end

  #def self.parse_alt(stream, key_field: nil, fields: nil, filename: nil, namespace: nil,  **kwargs, &block)
  #  options, key_field_name, field_names, first_line, preamble = parse_header(stream)

  #  if fields
  #    all_field_names ||= [key_field_name] + field_names
  #    positions = NamedArray.identify_name(all_field_names, fields)
  #    kwargs[:positions] = positions
  #    field_names = all_field_names.values_at *positions
  #  end

  #  if key_field
  #    all_field_names ||= [key_field_name] + field_names
  #    key = NamedArray.identify_name(all_field_names, key_field)
  #    kwargs[:key] = key
  #    key_field_name = all_field_names[key]
  #    if fields.nil?
  #      field_names = all_field_names - [key_field_name]
  #    end
  #  end

  #  options.each do |option,value|
  #    option = option.to_sym
  #    next unless KEY_PARAMETERS.include? option
  #    kwargs[option] = value unless kwargs.include?(option)
  #  end

  #  kwargs[:source_type] = options[:type]

  #  type = kwargs[:type] ||= :double
  #  if (data = kwargs[:data]) && data.respond_to?(:persistence_class)
  #    TSV.setup(data, type: type, key_field: key_field_name, fields: field_names)
  #    data.extend TSVAdapter
  #  end

  #  data = parse_stream(stream, first_line: first_line, **kwargs, &block)

  #  TSV.setup(data, :key_field => key_field_name, :fields => field_names, :type => type, filename: filename, namespace: namespace)

  #  data
  #end

end
