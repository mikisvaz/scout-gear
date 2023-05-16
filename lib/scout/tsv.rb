require_relative 'meta_extension'
require_relative 'tsv/util'
require_relative 'tsv/parser'
require_relative 'tsv/dumper'
require_relative 'tsv/persist'
require_relative 'tsv/index'
require_relative 'tsv/path'
require_relative 'tsv/traverse'
require_relative 'tsv/open'

module TSV
  extend MetaExtension
  extension_attr :key_field, :fields, :type, :filename, :namespace, :unnamed, :identifiers

  def self.str2options(str)
    field_options,_sep, rest =  str.partition("#")
    key, fields_str = field_options.split("~")

    fields = fields_str.nil? ? [] : fields_str.split(/,\s*/)

    rest = ":type=" << rest if rest =~ /^:?\w+$/
    rest_options = rest.nil? ? {} : IndiferentHash.string2hash(rest)

    {:key_field => key, :fields => fields}.merge(rest_options)
  end

  class << self
    alias old_setup setup
  end

  def self.setup(file, *args, **kwargs)
    options = args.pop if Hash === args.last
    type, option_str = args
    option_str, type = type, nil if option_str.nil? && String === type
    kwargs = IndiferentHash.add_defaults kwargs, TSV.str2options(option_str) if option_str
    old_setup(file, **kwargs)
  end

  def self.open(file, *args)
    options = args.pop if Hash === args.last
    type, option_str = args
    options_str, type = type, nil if option_str.nil? && String === type
    options = IndiferentHash.add_defaults options, TSV.str2options(option_str) if option_str
    options[:type] ||= type unless type.nil?
    persist, type, grep, invert_grep = IndiferentHash.process_options options, :persist, :persist_type, :grep, :invert_grep, :persist => false, :persist_type => "HDB"
    Persist.persist(file, type, options.merge(:persist => persist)) do |filename|
      data = filename ? ScoutCabinet.open(filename, true, type) : nil
      options[:data] = data if data
      options[:filename] = file
      Open.open(file, grep: grep, invert_grep: invert_grep) do |f|
        TSV.parse(f, **options)
      end
    end
  end
end

