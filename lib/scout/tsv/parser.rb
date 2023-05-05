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
      key = items.delete(key)
    else 
      key, items = items[key], items.values_at(*positions)
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

    key = key.partition(sep2).first if type == :double

    if cast
      items = cast_value(items, cast)
    end

    [key, items]
  end

  def self.parse_stream(stream, data: nil, merge: true, type: :list, fix: true, bar: false, first_line: nil, **kargs, &block)
    begin
      bar = Log::ProgressBar.new_bar(bar) if bar

      data = {} if data.nil?
      merge = false if type != :double
      line = first_line || stream.gets
      while line
        begin
          line.strip!
          line = Misc.fixutf8(line) if fix
          bar.tick if bar
          key, items = parse_line(line, type: type, **kargs)

          if block_given?
            res = block.call(key, items)
            data[key] = res unless res.nil?
            next
          end

          if ! merge || ! data.include?(key)
            data[key] = items
          else
            current = data[key]
            if merge == :concat
              items.each_with_index do |new,i|
                next if new.empty?
                current[i].concat(new)
              end
            else
              merged = []
              items.each_with_index do |new,i|
                next if new.empty?
                merged[i] = current[i] + new
              end
              data[key] = merged
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

  def self.parse_header(stream, fix: true, header_hash: '#', sep: "\n")
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

  def self.parse(stream, **kwargs)
    options, key_field, fields, first_line, preamble = parse_header(stream)

    options.each do |option,value|
      option = option.to_sym
      kwargs[option] = value unless kwargs.include?(option)
    end
    type = kwargs[:type] ||= :double
    data = parse_stream(stream, first_line: first_line, **kwargs)
    TSV.setup data, :key_field => key_field, :fields => fields, :type => type
  end
end
