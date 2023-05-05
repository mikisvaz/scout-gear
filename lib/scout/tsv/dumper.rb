module TSV
  class Dumper
    def self.header_lines(key_field, fields, entry_hash = nil)
      if Hash === entry_hash 
        sep = entry_hash[:sep] ? entry_hash[:sep] : "\t"
        preamble = entry_hash[:preamble]
        header_hash = entry_hash[:header_hash]
      end

      header_hash = "#" if header_hash.nil?

      preamble = "#: " << Misc.hash2string(entry_hash.merge(:key_field => nil, :fields => nil)) << "\n" if preamble.nil? and entry_hash and entry_hash.values.compact.any?

      str = "" 
      str << preamble.strip << "\n" if preamble and not preamble.empty?
      if fields
        if fields.empty?
          str << header_hash << (key_field || "ID").to_s << "\n" 
        else
          str << header_hash << (key_field || "ID").to_s << sep << (fields * sep) << "\n" 
        end
      end

      str
    end

    def self.header(options={})
      key_field, fields, sep, header_hash, preamble = IndiferentHash.process_options options, 
        :key_field, :fields, :sep, :header_hash, :preamble,
        :sep => "\t", :header_hash => "#", :preamble => true

      if fields.nil? || key_field.nil?
        fields_str = nil
      else
        fields_str = "#{header_hash}#{key_field}#{sep}#{fields*sep}"
      end

      if preamble 
        preamble_str = "#: " << IndiferentHash.hash2string(options)
      else
        preamble_str = nil
      end

      [preamble_str, fields_str].compact * "\n"
    end


    attr_accessor :options
    def initialize(options = {})
      @sep, @type = IndiferentHash.process_options options, :sep, :type, :sep => "\t", :type => :double
      @options = options
      @sout, @sin = Open.pipe
    end

    def init
      header = Dumper.header(@options.merge(:type => @type, :sep => @sep))
      @sin.puts header if header and ! header.empty?
    end

    def add(key, value)

      case @type
      when :single
        @sin.puts key + @sep + value
      when :list, :flat
        @sin.puts key + @sep + value * sep
      when :double
        @sin.puts key + @sep + value.collect{|v| v * "|" } * @sep
      end
    end

    def close
      @sin.close
    end

    def stream
      @sout
    end
  end

  def stream
    dumper = TSV::Dumper.new self.extension_attr_hash
    dumper.init
    Thread.new do 
      Thread.current["name"] = "Dumper thread"
      self.each do |k,v|
        dumper.add k, v
      end
      dumper.close
    end
    dumper.stream
  end

  def to_s
    stream.read
  end
end
