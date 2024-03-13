module TSV
  def self.paste_streams(streams, type: nil, sort: nil, merge: true, sort_memory: nil, sep: nil, preamble: nil, header: nil, same_fields: nil, fix_flat: nil, all_match: nil, field_prefix: nil)

    streams = streams.collect do |stream|
      case stream
      when(defined? Step and Step)
        stream.stream
      when Path
        stream.open
      when TSV::Dumper
        stream.stream
      when TSV
        stream.dumper_stream
      else
        stream
      end
    end.compact

    num_streams = streams.length

    streams = streams.collect do |stream|
      Open.sort_stream(stream, memory: sort_memory)
    end if sort

    begin

      lines         =[]
      fields        =[]
      sizes         =[]
      key_fields    =[]
      input_options =[]
      empty         =[]
      preambles     =[]
      parser_types  =[]

      type ||= :double

      streams = streams.collect do |stream|

        parser = TSV::Parser.new stream, type: type, sep: sep

        sfields = parser.fields

        if field_prefix
          index = streams.index stream
          prefix = field_prefix[index]

          sfields = sfields.collect{|f|[prefix, f]* ":"}
        end

        first_line = parser.first_line
        first_line = nil if first_line == ""

        lines         << first_line
        key_fields    << parser.key_field
        fields        << sfields
        sizes         << sfields.length if sfields
        input_options << parser.options
        preambles     << parser.preamble      if preamble and not parser.preamble.empty?
        parser_types  << parser.type

        empty         << stream               if parser.first_line.nil? || parser.first_line.empty?

        stream
      end


      all_fields = fields.dup

      key_field = key_fields.compact.first

      if same_fields
        fields = fields.first
      else
        fields = fields.compact.flatten
      end

      options = input_options.first 
      type ||= options[:type]
      type ||= :list if type == :single
      type ||= :double if type == :flat

      preamble_txt = case preamble
                     when TrueClass
                       preambles * "\n"
                     when String
                       if preamble[0]== '+'
                         preambles * "\n" + "\n" + preamble[1..-1]
                       else
                         preamble
                       end
                     else
                       nil
                     end

      empty_pos = empty.collect{|stream| streams.index stream}

      keys =[]
      parts =[]
      lines.each_with_index do |line,i|
        if line.nil? || line.empty?
          keys[i]= nil
          parts[i]= nil
        else
          vs = line.chomp.split(sep, -1)
          key, *p = vs
          keys[i]= key
          parts[i]= p
        end
        sizes[i] ||= parts[i].length unless parts[i].nil?
      end
      done_streams =[]

      fields = nil if fields && fields.empty?
      dumper = TSV::Dumper.new key_field: key_field, fields: fields, type: type
      dumper.init(preamble: !!key_field)

      t = Thread.new do
        Thread.report_on_exception = false
        Thread.current["name"] = "Paste streams"

        last_min = nil
        while lines.reject{|line| line.nil?}.any?
          min = keys.compact.sort.first
          break if min.nil?
          new_values =[]

          skip = all_match && keys.uniq !=[min]

          keys.each_with_index do |key,i|
            case key
            when min
              new_values << parts[i]

              begin
                line = lines[i]= begin
                                   streams[i].gets
                               rescue
                                 Log.exception $!
                                 nil
                               end
              if line.nil?
                keys[i]= nil
                parts[i]= nil
              else
                k, *p = line.chomp.split(sep, -1)
                p = p.collect{|e| e.nil? ? "" : e }

                if k == keys[i]
                  new_values = NamedArray.zip_fields(new_values).zip(p).collect{|p| [p.flatten * "|"] }
                  raise TryAgain 
                end
                keys[i]= k
                parts[i]= p
              end
            rescue TryAgain
              keys[i]= nil
              parts[i]= nil
              Log.debug "Skipping repeated key in stream #{i}: #{key} - #{min}"
              retry
            end
          else
            p = [nil] * sizes[i]
            new_values << p
          end
        end

        next if skip

        if same_fields
          new_values_same = []
          new_values.each do |list|
            list.each_with_index do |l,i|
              new_values_same[i] ||= []
              new_values_same[i] << l
            end
          end
          new_values = new_values_same
        else
          new_values = new_values.inject([]){|acc,l| acc.concat l }
        end

        dumper.add min, new_values
      end

      dumper.close

      streams.each do |stream|
        stream.close if stream.respond_to?(:close) && ! stream.closed?
        stream.join if stream.respond_to? :join
      end
      end
    rescue Aborted
      Log.error "Aborted pasting streams #{streams.inspect}: #{$!.message}"
      streams.each do |stream|
        stream.abort if stream.respond_to? :abort
      end
      raise $!
    rescue Exception
      Log.error "Exception pasting streams #{streams.inspect}: #{$!.message}"
      streams.each do |stream|
        stream.abort if stream.respond_to? :abort
      end
      raise $!
    end

    Thread.pass until t["name"]

    ConcurrentStream.setup(dumper.stream, threads: [t])
  end

end
