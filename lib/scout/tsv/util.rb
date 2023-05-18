#require_relative '../../../modules/rbbt-util/lib/rbbt/tsv/manipulate'
#Log.warn "USING OLD RBBT CODE: #{__FILE__}"
require_relative 'traverse'
require_relative 'util/process'
require_relative 'util/select'
module TSV
  def [](key, *rest)
    v = super(key, *rest)
    NamedArray.setup(v, @fields, key) unless @unnamed || ! (Array === v)
    v
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

  def with_unnamed
    begin
      old_unnamed = @unnamed
      @unnamed = true
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
    filename = "No filename" if filename.nil? || filename.empty?
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

  def fingerprint
    "TSV:{"<< Log.fingerprint(self.all_fields|| []) << ";" << Log.fingerprint(self.keys) << "}"
  end

  def digest_str
    fingerprint
  end

  def inspect
    fingerprint
  end
end
