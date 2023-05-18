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

      if preamble && options.values.compact.any?
        preamble_str = "#: " << IndiferentHash.hash2string(options)
      else
        preamble_str = nil
      end

      [preamble_str, fields_str].compact * "\n"
    end


    attr_accessor :options, :initialized, :type, :sep
    def initialize(options = {})
      @sep, @type = IndiferentHash.process_options options, 
        :sep, :type, 
        :sep => "\t", :type => :double
      @options = options
      @sout, @sin = Open.pipe
      @initialized = false
      @mutex = Mutex.new
      ConcurrentStream.setup(@sin, pair: @sout)
      ConcurrentStream.setup(@sout, pair: @sin)
    end

    def init(preamble: true)
      header = Dumper.header(@options.merge(type: @type, sep: @sep, preamble: preamble))
      @mutex.synchronize do
        @initialized = true
        @sin.puts header if header and ! header.empty?
      end
    end

    def add(key, value)
      @mutex.synchronize do

        case @type
        when :single
          @sin.puts key + @sep + value
        when :list, :flat
          @sin.puts key + @sep + value * @sep
        when :double
          @sin.puts key + @sep + value.collect{|v| v * "|" } * @sep
        end
      end
    end

    def close
      @sin.close
      @sin.join
    end

    def stream
      @sout
    end

    def abort(exception=nil)
      @sin.abort(exception)
    end

    def tsv(*args)
      TSV.open(stream, *args)
    end
  end

  def dumper_stream(options = {})
    preamble = IndiferentHash.process_options options, :preamble, :preamble => true
    dumper = TSV::Dumper.new self.extension_attr_hash.merge(options)
    dumper.init(preamble: preamble)
    t = Thread.new do 
      begin
        Thread.current.report_on_exception = true
        Thread.current["name"] = "Dumper thread"
        self.each do |k,v|
          dumper.add k, v
        end
        dumper.close
      rescue
        dumper.abort($!)
      end
    end
    Thread.pass until t["name"]
    s = dumper.stream
    ConcurrentStream.setup(s, :threads => [t])
    s
  end

  def to_s(options = {})
    dumper_stream(options).read
  end
end
