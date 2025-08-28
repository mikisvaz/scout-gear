require 'scout/named_array'
module TSV
  def self.acceptable_parser_options(func = nil)
    if func.nil?
      TSV.method(:parse_line).parameters.collect{|a| a.last } +
        TSV.method(:parse_stream).parameters.collect{|a| a.last } +
        TSV.method(:parse).parameters.collect{|a| a.last } - [:line, :block]
    else
      TSV.method(func).parameters.collect{|a| a.last }
    end.uniq
  end

  def self.cast_value(value, cast)
    if Array === value
      value.collect{|e| cast_value(e, cast) }
    else
      if Proc === cast
        cast.call value
      else
        if value.nil? || value == ""
          nil
        else
          value.send(cast)
        end
      end
    end
  end

  def self.parse_line(line, type: :list, key: 0, positions: nil, sep: "\t", sep2: "|", cast: nil, select: nil, field_names: nil)
    items = line.split(sep, -1)

    return nil if select && ! TSV.select(items[0], items[1..-1], select, fields: field_names, type: type, sep: sep2)

    if String === key
      raise "Key by name, but no field names" if field_names.nil?
      key = field_names.index key
      raise "Key #{key} not found in field names #{Log.fingerprint field_names}" if key.nil?
    end

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

  def self.parse_stream(stream, data: nil, source_type: nil, sep: "\t", type: :list, merge: true, one2one: false, fix: true, bar: false, first_line: nil, field_names: nil, head: nil, **kwargs, &block)
    begin
      bar = "Parsing #{Log.fingerprint stream}" if TrueClass === bar
      bar = Log::ProgressBar.get_obj_bar(stream, bar) if bar
      bar.init if bar

      source_type = type if source_type.nil?

      type_swap_key = [source_type.to_s, type.to_s] * "_"

      same_type = source_type.to_s == type.to_s

      if data && data.respond_to?(:load_stream) && 
          data.serializer.to_s.include?("String") &&
          same_type && 
          ! (head || kwargs[:cast] || kwargs[:positions] || (kwargs[:key] && kwargs[:key] != 0) || Proc === fix ) &&
          (sep.nil? || sep == "\t")


        Log.debug "Loading #{Log.fingerprint stream} directly into #{Log.fingerprint data}"
        if first_line
          full_stream = Open.open_pipe do |sin|
            sin.puts first_line
            Open.consume_stream(stream, false, sin)
          end
          data.load_stream(full_stream)
        else
          data.load_stream(stream)
        end

        return data
      end


      data = {} if data.nil?
      merge = false if type != :double && type != :flat
      line = first_line || stream.gets
      while line 
        break if head && head <= 0
        begin
          line.chomp!
          if Proc === fix
            line = fix.call line
            break if (FalseClass === line) || :break == line
            next if line.nil?
          elsif fix
            line = Misc.fixutf8(line)
          end
          bar.tick if bar

          if type == :array || type == :line
            block.call line
            next
          elsif type == :matrix
            parts = line.split(sep)
            block.call parts
            next
          end

          key, items = parse_line(line, type: source_type, field_names: field_names, sep: sep, **kwargs)

          next if key.nil?

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
              case type_swap_key
              when "single_single"
                these_items
              when "list_single"
                these_items.first
              when "flat_single"
                these_items.first
              when "double_single"
                these_items.first.first
              when "single_list"
                [these_items]
              when "list_list"
                these_items
              when "flat_list"
                these_items
              when "double_list"
                these_items.collect{|l| l.first }
              when "single_flat"
                [these_items]
              when "list_flat"
                these_items
              when "flat_flat"
                these_items
              when "double_flat"
                these_items.flatten
              when "single_double"
                [[these_items]]
              when "list_double"
                these_items.collect{|l| l.nil? ? [] : [l] }
              when "flat_double"
                [these_items]
              when "double_double"
                these_items
              end

            if block_given?
              res = block.call(key, these_items, field_names)
              data[key] = res unless res.nil? || FalseClass === data
              next
            end

            if ! merge || ! data.include?(key)
              these_items = these_items.collect{|i| i.empty? ? [nil] : i } if type == :double && one2one
              data[key] = these_items
            elsif type == :double
              current = data[key]
              if merge == :concat
                these_items.each_with_index do |new,i|
                  new = one2one ? [nil] : [] if new.empty?
                  current[i].concat(new)
                end
              else
                merged = []
                these_items.each_with_index do |new,i|
                  new = one2one ? [nil] : [] if new.empty?
                  merged[i] = (current[i] || []) + new
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
        rescue Exception
          raise stream.stream_exception if stream.respond_to?(:stream_exception) && stream.stream_exception
          stream.abort($!) if stream.respond_to?(:abort)
          raise $!
        ensure
          head = head - 1 if head
          if stream.closed?
            line = nil
          else
            line = stream.gets 
          end
        end
      end
      data
    ensure
      if stream.respond_to?(:stream_exception) && stream.stream_exception
        bar.remove(stream.stream_exception)
      else
        bar.remove
      end if bar

      if stream.respond_to?(:join)
        eof = begin
                stream.eof?
              rescue IOError
                true
              end
        stream.join if eof
      end
    end
  end

  def self.parse_header(stream, fix: true, header_hash: '#', sep: "\t")
    sep = "\t" if sep.nil?
    if (Path === stream) || ((String === stream) && Path.is_filename?(stream))
      Open.open(stream) do |f|
        return parse_header(f, fix: fix, header_hash: header_hash, sep: sep)
      end
    end

    if IO === stream && stream.closed?
      stream.join if stream.respond_to?(:join)
      raise "Closed stream" 
    end

    opts = {}
    preamble = []

    # Get line

    begin
      #Thread.pass while IO.select([stream], nil, nil, 1).nil? if IO === stream
      line = stream.gets
      return {} if line.nil?
      line = Misc.fixutf8 line.chomp if fix

      # Process options line
      if line and (String === header_hash && m = line.match(/^#{header_hash}: (.*)/))
        opts = IndiferentHash.string2hash m.captures.first.chomp
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
      sep = opts[:sep] if opts[:sep]

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

      opts[:type] = opts[:type].to_sym if opts[:type]
      opts[:cast] = opts[:cast].to_sym if opts[:cast]

      all_fields = [key_field] + fields if key_field && fields
      namespace = opts[:namespace]
      NamedArray.setup([opts, key_field, fields, first_line, preamble, all_fields, namespace], %w(options key_field fields first_line preamble all_fields namespace))
    rescue Exception
      raise stream.stream_exception if stream.respond_to?(:stream_exception) && stream.stream_exception
      stream.abort($!) if stream.respond_to?(:abort)
      raise $!
    end
  end

  def self.parse_options(...)
    parse_header(...)[:options]
  end

  KEY_PARAMETERS = begin
                     params = []
                     (method(:parse_line).parameters + method(:parse_stream).parameters).each do |type, name|
                       params << name if type == :key
                     end
                     params
                   end

  class Parser
    attr_accessor :stream, :source_options, :key_field, :fields, :type, :first_line, :preamble
    def initialize(file, fix: true, header_hash: "#", sep: "\t", type: :double)
      if IO === file
        @stream = file
      else
        @stream = Open.open(file)
      end
      @fix = fix
      @source_options, @key_field, @fields, @first_line, @preamble = TSV.parse_header(@stream, fix:fix, header_hash:header_hash, sep:sep)
      @source_options[:filename] = file if Path.is_filename?(file)
      @source_options[:sep] = sep if @source_options[:sep].nil?
      @source_options.merge!(:key_field => @key_field, :fields => @fields)
      @type = @source_options[:type] || type
    end

    def options
      IndiferentHash.add_defaults @source_options.dup, type: type, key_field: key_field, fields: fields
    end

    def all_fields
      return nil if @fields.nil?
      [@key_field] + @fields
    end

    def key_field=(key_field)
      @source_options[:key_field] = @key_field = key_field
    end
    
    def fields=(fields)
      @source_options[:fields] = @fields = fields
    end

    def identify_field(name)
      TSV.identify_field(@key_field, @fields, name)
    end

    def traverse(key_field: nil, fields: nil, filename: nil, namespace: nil,  **kwargs, &block)
      kwargs[:type] ||=  self.source_options[:type] ||= @type
      kwargs[:type] = kwargs[:type].to_sym if kwargs[:type]

      if fields
        if @fields
          all_field_names ||= [@key_field] + @fields
          fields = all_field_names if fields == :all
          positions = NamedArray.identify_name(all_field_names, fields)

          raise "Not all fields (#{Log.fingerprint fields}) identified in #{Log.fingerprint all_field_names}" if positions.include?(nil)
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

      kwargs[:positions] = nil if @type == :flat

      if key_field
        if @fields
          all_field_names ||= [@key_field] + @fields
          key = NamedArray.identify_name(all_field_names, key_field)
          kwargs[:key] = key == :key ? 0 : key
          key_field_name = (key.nil? || key == :key) ? @key_field : all_field_names[key]
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

      @source_options.each do |option,value|
        option = option.to_sym
        next unless KEY_PARAMETERS.include? option
        kwargs[option] = value unless kwargs.include?(option)
      end

      kwargs[:source_type] = @source_options[:type]
      kwargs[:data] = false if kwargs[:data].nil?

      if kwargs[:tsv_grep]
        data = with_stream do |stream|
          grep_stream = Open.grep(stream, kwargs.delete(:tsv_grep), kwargs.delete(:tsv_invert_grep))
          TSV.parse_stream(grep_stream, first_line: nil, fix: @fix, field_names: @fields, **kwargs, &block)
        end
      else
        data = TSV.parse_stream(@stream, first_line: @first_line, fix: @fix, field_names: @fields, **kwargs, &block)
      end

      if data
        TSV.setup(data, @source_options.merge(:key_field => key_field_name, :fields => field_names, :type => @type))
      else
        [key_field || self.key_field, fields || self.fields]
      end
    end

    def fingerprint
      "Parser:{" + Log.fingerprint(self.all_fields|| []) << "}"
    end

    def digest_str
      fingerprint
    end

    def inspect
      fingerprint
    end

    def with_stream
      sout = Open.open_pipe do |sin|
        sin.puts @first_line
        Open.consume_stream(@stream, false, sin)
      end
      yield sout
    end
  end

  def self.parse(stream, fix: true, header_hash: "#", sep: "\t", filename: nil, namespace: nil, unnamed: nil, serializer: nil, **kwargs, &block)
    parser = TSV::Parser === stream ? stream : TSV::Parser.new(stream, fix: fix, header_hash: header_hash, sep: sep)

    cast = kwargs[:cast]
    cast = parser.options[:cast] if cast.nil?
    identifiers = kwargs.delete(:identifiers)
    type = kwargs[:type] ||=  parser.options[:type] ||= :double

    if (data = kwargs[:data]) && data.respond_to?(:persistence_class)
      TSV.setup(data, type: type)
      data.extend TSVAdapter
      serializer ||= if cast
                       case [cast, type]
                       when [:to_i, :single]
                         :integer
                       when [:to_i, :list], [:to_i, :flat]
                         :integer_array
                       when [:to_f, :single]
                         :float
                       when [:to_f, :list], [:to_f, :flat]
                         :float_array
                       when [:to_f, :double], [:to_i, :double]
                         :marshal
                       else
                         type
                       end
                     else
                       type
                     end
      data.serializer = TSVAdapter::SERIALIZER_ALIAS[serializer] || serializer
    end

    kwargs[:data] = {} if kwargs[:data].nil?

    data = parser.traverse **kwargs, &block
    data.type = type
    data.cast = cast
    data.filename = filename || parser.options[:filename] if data.filename.nil?
    data.namespace = namespace || parser.options[:namespace] if data.namespace.nil?
    data.identifiers = identifiers || parser.options[:identifiers] if data.identifiers.nil?
    data.unnamed = unnamed
    data.save_annotation_hash if data.respond_to?(:save_annotation_hash)
    data
  end
end
