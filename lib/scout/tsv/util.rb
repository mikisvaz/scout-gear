#require_relative '../../../modules/rbbt-util/lib/rbbt/tsv/manipulate'
#Log.warn "USING OLD RBBT CODE: #{__FILE__}"
require_relative 'traverse'
require_relative 'util/process'
require_relative 'util/select'
module TSV
  def [](*args)
    v = super(*args)
    NamedArray.setup(v, @fields) unless @unnamed || ! (Array === v)
    v
  end
  [:each, :collect, :map].each do |method|
    define_method(method) do |*args,&block|
      super(*args) do |k,v|
        NamedArray.setup(v, @fields) unless @unnamed || ! (Array === v)
        block.call k, v
      end
    end
  end

  #[:select, :reject].each do |method|
  #  define_method(method) do |*args,&block|
  #    res = super(*args) do |k,v|
  #      NamedArray.setup(v, @fields) unless @unnamed
  #      block.call k, v
  #    end
  #    self.annotate(res)
  #    res
  #  end
  #end

  def with_unnamed
    begin
      old_unnamed = unnamed
      unnamed = true
      yield
    ensure
      unnamed = old_unnamed
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
    [@key_field] + @fields
  end

  def fingerprint
    "TSV:{"<< Log.fingerprint(self.all_fields|| []) << ";" << Log.fingerprint(self.keys) << "}"
  end
end
