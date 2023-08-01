require 'scout/meta_extension'
require_relative 'tsv/util'
require_relative 'tsv/parser'
require_relative 'tsv/dumper'
require_relative 'tsv/transformer'
require_relative 'tsv/persist'
require_relative 'tsv/index'
require_relative 'tsv/path'
require_relative 'tsv/traverse'
require_relative 'tsv/open'
require_relative 'tsv/attach'
require_relative 'tsv/change_id'
require_relative 'tsv/stream'

module TSV
  extend MetaExtension
  extension_attr :key_field, :fields, :type, :cast, :filename, :namespace, :unnamed, :identifiers

  def self.str2options(str)
    field_options,_sep, rest =  str.partition("#")
    key, fields_str = field_options.split("~")

    fields = fields_str.nil? ? [] : fields_str.split(/,\s*/)

    rest = ":type=" << rest if rest =~ /^:?\w+$/
    rest_options = rest.nil? ? {} : IndiferentHash.string2hash(rest)

    {:key_field => key, :fields => fields}.merge(rest_options)
  end

  def self.str_setup(option_str, obj)
    options = TSV.str2options(option_str) 
    setup(obj, options)
  end

  def self.open(file, options = {})
    grep, invert_grep = IndiferentHash.process_options options, :grep, :invert_grep, :persist => false

    persist_options = IndiferentHash.pull_keys options, :persist
    persist_options = IndiferentHash.add_defaults persist_options, :prefix => "TSV", :type => :HDB

    file = StringIO.new file if String === file && ! (Path === file) && file.index("\n")
    Persist.persist(file, persist_options[:type], persist_options.merge(:other_options => options)) do |filename|
      if filename
        data = case persist_options[:type]
               when :HDB, :BDB
                 ScoutCabinet.open(filename, true, persist_options[:type])
               when :tkh, :tkt, :tks
                 ScoutTKRZW.open(filename, true, persist_options[:type])
               end
      else
        data = nil
      end
      options[:data] = data if data
      options[:filename] = file

      if data
        Log.debug "TSV open #{Log.fingerprint file} into #{Log.fingerprint data}"
      else
        Log.debug "TSV open #{Log.fingerprint file}"
      end

      Open.open(file, grep: grep, invert_grep: invert_grep) do |f|
        TSV.parse(f, **options)
      end
    end
  end
end

