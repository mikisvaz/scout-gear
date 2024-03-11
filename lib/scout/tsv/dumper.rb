module TSV
  class Dumper
    def self.header(options={})
      key_field, fields, sep, header_hash, preamble, unnamed = IndiferentHash.process_options options, 
        :key_field, :fields, :sep, :header_hash, :preamble, :unnamed,
        :sep => "\t", :header_hash => "#", :preamble => true

      if fields.nil?
        fields_str = nil
      elsif fields.empty?
        fields_str = "#{header_hash}#{key_field || "Id"}"
      else
        fields_str = "#{header_hash}#{key_field || "Id"}#{sep}#{fields*sep}"
      end

      if String === preamble
        preamble_str = preamble
      elsif preamble && options.values.compact.any?
        preamble_str = "#: " << IndiferentHash.hash2string(options)
      else
        preamble_str = nil
      end

      preamble_str = preamble_str.strip if preamble_str
      [preamble_str, fields_str].compact * "\n"
    end


    attr_accessor :options, :initialized, :type, :sep
    def initialize(options = {})
      options = options.options.merge(sep: nil) if TSV::Parser === options || TSV === options
      @sep, @type = IndiferentHash.process_options options, 
        :sep, :type, 
        :sep => "\t", :type => :double
      @options = options
      @options[:type] = @type
      @sout, @sin = Open.pipe
      Log.low{"Dumper pipe #{[Log.fingerprint(@sin), Log.fingerprint(@sout)] * " -> "}"}
      @initialized = false
      @mutex = Mutex.new
      ConcurrentStream.setup(@sin, pair: @sout)
      ConcurrentStream.setup(@sout, pair: @sin)
    end

    def key_field
      @options[:key_field]
    end
    
    def fields
      @options[:fields]
    end

    def key_field=(key_field)
      @options[:key_field] = key_field
    end
    
    def fields=(fields)
      @options[:fields] = fields
    end

    def all_fields
      return nil if fields.nil?
      [key_field] + fields
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

        key = key.to_s unless String === key
        if value.nil? || value.empty?
          @sin.puts key
        else
          case @type
          when :single
            @sin.puts key + @sep + value.to_s
          when :list, :flat
            @sin.puts key + @sep + value * @sep
          when :double
            @sin.puts key + @sep + value.collect{|v| Array === v ? v * "|" : v } * @sep
          end
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

    def fingerprint
      "Dumper:{"<< Log.fingerprint(self.all_fields|| []) << "}"
    end

    def digest_str
      fingerprint
    end

    def inspect
      fingerprint
    end
  end

  def dumper_stream(options = {})
    preamble, unmerge, keys = IndiferentHash.process_options options, :preamble, :unmerge, :keys,
      :preamble => true, :unmerge => false
    unmerge = false unless @type === :double
    dumper = TSV::Dumper.new self.extension_attr_hash.merge(options)
    t = Thread.new do 
      begin
        Thread.current.report_on_exception = true
        Thread.current["name"] = "Dumper thread"
        dumper.init(preamble: preamble)

        dump_entry = Proc.new do |k,value_list|
          if unmerge
            max = value_list.collect{|v| v.length}.max

            if unmerge == :expand and max > 1
              value_list = value_list.collect do |values|
                if values.length == 1
                  [values.first] * max
                else
                  values
                end
              end
            end

            NamedArray.zip_fields(value_list).each do |values|
              dumper.add k, values
            end
          else
            dumper.add k, value_list
          end
        end

        if keys
          keys.each do |k|
            dump_entry.call k, self[k]
          end
        else
          self.each &dump_entry
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

  alias stream dumper_stream
end
