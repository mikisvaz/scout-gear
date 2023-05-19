require_relative '../named_array'
module TSV
  def self.cast_value(value, cast)
    if Array === value
      value.collect{|e| cast_value(e, cast) }
    else
      if Proc === cast
        cast.call value
      else
        value.send(cast)
      end
    end
  end

  def self.parse_line(line, type: :list, key: 0, positions: nil, sep: "\t", sep2: "|", cast: nil)
    items = line.split(sep, -1)

    if positions.nil? && key == 0
      key = items.shift
    elsif positions.nil?
      if type == :flat
        key = items[1..-1].collect{|e| e.split(sep2, -1) }.flatten
        items = items.slice(0,1)
      else
        key = items.delete_at(key)
      end
      key = key.split(sep2) if type == :double
    else 
      key, items = items[key], items.values_at(*positions)
      key = key.split(sep2) if type == :double || type == :flat
    end

    items = case type
            when :list
              items
            when :single
              items.first
            when :flat
              items.collect{|i| i.split(sep2, -1) }.flatten
            when :double
              items.collect{|i| i.nil? ? [] : i.split(sep2, -1) }
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
      merge = false if type != :double && type != :flat
      line = first_line || stream.gets
      while line
        begin
          line.strip!
          if Proc === fix
            line = fix.call line
          elsif fix
            line = Misc.fixutf8(line)
          end
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

            these_items = 
              case [source_type, type]
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
            elsif type == :double
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
            elsif type == :flat
              current = data[key]
              if merge == :concat
                current[i].concat these_items
              else
                data[key] = current + these_items
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
      if line && fix
        if Proc === fix
          line = fix.call line
        else
          line = Misc.fixutf8 line.chomp if line && fix
        end
      end
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

    options[:type] = options[:type].to_sym if options[:type]
    options[:cast] = options[:cast].to_sym if options[:cast]

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
      @fix = fix
      @options, @key_field, @fields, @first_line, @preamble = TSV.parse_header(@stream, fix:fix, header_hash:header_hash, sep:sep)
      @options[:sep] = sep if @options[:sep].nil?
    end

    def all_options
      options.merge(:key_field => @key_field, :fields => @fields)
    end

    def all_fields
      [@key_field] + @fields
    end

    def identify_field(name)
      TSV.identify_field(@key_field, @fields, name)
    end


    def traverse(key_field: nil, fields: nil, filename: nil, namespace: nil,  **kwargs, &block)
      kwargs[:type] ||=  self.options[:type] ||= :double
      kwargs[:type] = kwargs[:type].to_sym if kwargs[:type]

      if fields
        if @fields
          all_field_names ||= [@key_field] + @fields
          fields = all_field_names if fields == :all
          positions = NamedArray.identify_name(all_field_names, fields)
          kwargs[:positions] = positions
          field_names = all_field_names.values_at *positions
        elsif fields.reject{|f| Numeric === f}.empty?
          positions = fields
          kwargs[:positions] = positions
        else
          raise "Non-numeric fields specified, but no field names available"
        end
      else
        field_names = @fields
      end

      if key_field
        if @fields
          all_field_names ||= [@key_field] + @fields
          key = NamedArray.identify_name(all_field_names, key_field)
          kwargs[:key] = key == :key ? 0 : key
          key_field_name = key === :key ? @key_field : all_field_names[key]
          if fields.nil?
            field_names = all_field_names - [key_field_name]
          end
        else
          kwargs[:key] = key_field == :key ? 0 : key_field
          key = key_field
        end
      else
        key_field_name = @key_field
      end

      if field_names && (kwargs[:type] == :single || kwargs[:type] == :flat)
        field_names = field_names.slice(0,1)
      end

      @options.each do |option,value|
        option = option.to_sym
        next unless KEY_PARAMETERS.include? option
        kwargs[option] = value unless kwargs.include?(option)
      end

      kwargs[:source_type] = @options[:type]
      kwargs[:data] = false if kwargs[:data].nil?

      data = TSV.parse_stream(@stream, first_line: @first_line, fix: @fix, **kwargs, &block)

      if data
        TSV.setup(data, :key_field => key_field_name, :fields => field_names, :type => @type)
      else
        self
      end
    end
  end

  def self.parse(stream, fix: true, header_hash: "#", sep: "\t", filename: nil, namespace: nil, unnamed: false, serializer: nil, **kwargs, &block)
    parser = TSV::Parser.new stream, fix: fix, header_hash: header_hash, sep: sep

    cast = parser.options[:cast] || kwargs[:cast]
    type = kwargs[:type] ||=  parser.options[:type] ||= :double
    if (data = kwargs[:data]) && data.respond_to?(:persistence_class)
      TSV.setup(data, type: type)
      data.extend TSVAdapter
      if serializer
        data.serializer = serializer
      elsif cast
        data.serializer = 
          case [cast, type]
          when [:to_i, :single]
            :integer
          when [:to_i, :list], [:to_i, :flat]
            :integer_array
          when [:to_f, :single]
            :float
          when [:to_f, :list], [:to_f, :flat]
            :float_array
          else
            type
          end
      else
        data.serializer = type
      end
    end

    kwargs[:data] = {} if kwargs[:data].nil?

    data = parser.traverse **kwargs, &block
    data.type = type
    data.filename = filename
    data.namespace = namespace
    data.unnamed = unnamed
    data
  end
end
