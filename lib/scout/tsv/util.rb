#require_relative '../../../modules/rbbt-util/lib/rbbt/tsv/manipulate'
#Log.warn "USING OLD RBBT CODE: #{__FILE__}"
require_relative 'traverse'
require_relative 'util/filter'
require_relative 'util/process'
require_relative 'util/select'
require_relative 'util/reorder'
require_relative 'util/unzip'
require_relative 'util/sort'
require_relative 'util/melt'
module TSV

  def self.field_match_counts(file, values, options = {})
    options = IndiferentHash.add_defaults options, :persist_prefix => "Field_Matches"
    persist_options = IndiferentHash.pull_keys options, :persist

    filename = TSV === file ? file.filename : file
    path = Persist.persist filename, :string, persist_options.merge(:no_load => true) do
      tsv = TSV === file ? file : TSV.open(file, options)

      text = ""
      fields = nil
      tsv.tap{|e| e.unnamed =  true; fields = e.fields}.through do |gene, names|
        names.zip(fields).each do |list, format|
          list = [list] unless Array === list
          list.delete_if do |name| name.empty? end
          next if list.empty?
          text << list.collect{|name| [name, format] * "\t"} * "\n" << "\n"
        end
        text << [gene, tsv.key_field] * "\t" << "\n"
      end
      text
    end

    TmpFile.with_file(values.uniq * "\n", false) do |value_file|
      cmd = "cat '#{ path }' | sed 's/\\t/\\tHEADERNOMATCH/' | grep -w -F -f '#{ value_file }' | sed 's/HEADERNOMATCH//' |sort -u|cut -f 2  |sort|uniq -c|sed 's/^ *//;s/ /\t/'"
      begin
        TSV.open(CMD.cmd(cmd), :key_field => 1, :fields => [0], :type => :single, :cast => :to_i)
      rescue
        Log.exception $!
        TSV.setup({}, :type => :single, :cast => :to_i)
      end
    end
  end

  def self.identify_field(key_field, fields, name, strict: nil)
    return :key if name == :key || (! strict && NamedArray.field_match(key_field, name))
    name.collect!{|n| key_field == n ? :key : n } if Array === name
    NamedArray.identify_name(fields, name, strict: strict)
  end

  def identify_field(name, strict: nil)
    TSV.identify_field(@key_field, @fields, name, strict: strict)
  end

  def [](key, *rest)
    v = super(key, *rest)
    NamedArray.setup(v, @fields, key) unless @unnamed || ! (Array === v)
    v
  end

  def options
    extension_attr_hash
  end

  def zip_new(key, values, insitu: :lax)
    values = values.collect{|v| Array === v ? v : [v] } unless Array === values.first
    if current_values = self[key]
      if insitu == :lax
        self[key] = NamedArray.add_zipped(current_values, values)
      elsif insitu
        NamedArray.add_zipped(current_values, values)
      else
        self[key] = NamedArray.add_zipped(current_values.dup, values)
      end
    else
      if insitu && insitu != :lax
        self[key] = values.dup
      else
        self[key] = values
      end
    end
  end

  def each(*args, &block)
    if block_given?
      super(*args) do |k,v|
        NamedArray.setup(v, @fields) unless @unnamed || ! (Array === v)
        block.call(k, v)
      end
    else
      super(*args)
    end
  end

  def collect(*args, &block)
    if block_given?
      res = []
      each do |k,v|
        res << yield(k, v)
      end
      res
    else
      super(*args)
    end
  end

  def with_unnamed(unnamed = true)
    begin
      old_unnamed = @unnamed
      @unnamed = unnamed
      yield
    ensure
      @unnamed = old_unnamed
    end
  end

  def summary
    key = nil
    values = nil
    self.each do |k, v|
      key = k
      values = v
      break
    end

    filename = @filename
    filename = "No filename" if filename.nil? || String === filename && filename.empty?
    filename.find if Path === filename 
    filename = File.basename(filename) + " [" + File.basename(persistence_path) + "]" if respond_to?(:persistence_path) and persistence_path

    with_unnamed do
      <<-EOF
Filename = #{filename}
Key field = #{key_field || "*No key field*"}
Fields = #{fields ? Log.fingerprint(fields) : "*No field info*"}
Type = #{type}
Size = #{size}
namespace = #{Log.fingerprint namespace}
identifiers = #{Log.fingerprint identifiers}
Example:
  - #{key} -- #{Log.fingerprint values }
      EOF
    end
  end

  def all_fields
    return [] if @fields.nil?
    [@key_field] + @fields
  end

  def self.all_fields(file)
    if file.respond_to?(:all_fields)
      file.all_fields
    else
      TSV.parse_header(file)["all_fields"]
    end
  end

  def options
    self.extension_attr_hash
  end

  def fingerprint
    "TSV:{"<< Log.fingerprint(self.all_fields|| []) << ";" << Log.fingerprint(self.keys) << "}"
  end

  def digest_str
    "TSV:{"<< Log.fingerprint(self.all_fields|| []) << ";" << Log.fingerprint(self.keys) << ";" << Log.fingerprint(self.values) << "}"
  end

  def inspect
    fingerprint
  end

  def merge(other)
    self.annotate(super(other))
  end

end
