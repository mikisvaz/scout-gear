require 'scout/annotation'
require_relative 'tsv/util'
require_relative 'tsv/parser'
require_relative 'tsv/dumper'
require_relative 'tsv/transformer'
require_relative 'persist/tsv'
require_relative 'tsv/index'
require_relative 'tsv/path'
require_relative 'tsv/traverse'
require_relative 'tsv/open'
require_relative 'tsv/attach'
require_relative 'tsv/change_id'
require_relative 'tsv/stream'
require_relative 'tsv/annotation'
require_relative 'tsv/csv'

module TSV
  extend Annotation
  annotation :key_field, :fields, :type, :cast, :filename, :namespace, :unnamed, :identifiers, :serializer, :entity_options


  def self.str2options(str)
    field_options,_sep, rest =  str.partition("#")
    key, fields_str = field_options.split("~")

    fields = fields_str.nil? ? [] : fields_str.split(/,\s*/)

    rest = ":type=" << rest if rest =~ /^:?\w+$/
    rest_options = rest.nil? ? {} : IndiferentHash.string2hash(rest)

    {:key_field => key, :fields => fields}.merge(rest_options)
  end

  class << self
    alias original_setup setup

    def setup(obj, *rest, &block)

      if rest.length == 1 && String === rest.first
        options = TSV.str2options(rest.first)
        if Array === obj
          default_value = case options[:type]
                          when :double, :flat, :list, nil
                            []
                          when :single
                            nil
                          end
          obj = IndiferentHash.array2hash(obj, default_value)
        end
        original_setup(obj, options, &block)
      else
        if Array === obj
          options = rest.first if Hash === rest.first
          options ||= {}
          default_value = case options[:type]
                          when :double, :flat, :list, nil
                            []
                          when :single
                            nil
                          end
          obj = IndiferentHash.array2hash(obj, default_value)
        end
        original_setup(obj, *rest, &block)
      end

      obj.save_annotation_hash if obj.respond_to?(:save_annotation_hash)

      obj
    end
  end

  def self.str_setup(option_str, obj)
    options = TSV.str2options(option_str) 
    setup(obj, **options)
  end

  def self.open(file, options = {})
    grep, invert_grep, fixed_grep, nocache, monitor, entity_options = IndiferentHash.process_options options, :grep, :invert_grep, :fixed_grep, :nocache, :monitor, :entity_options

    persist_options = IndiferentHash.pull_keys options, :persist
    persist_options = IndiferentHash.add_defaults persist_options, prefix: "TSV", type: :HDB, persist: false
    persist_options[:data] ||= options[:data]

    file = StringIO.new file if String === file && ! (Path === file) && file.index("\n")

    source_name, options = 
      case file
      when StringIO
        [file.inspect, options]
      when TSV::Parser
        [file.options[:filename], file.options]
      else
        [file, options]
      end

    Persist.tsv(source_name, options, persist_options: persist_options) do |data|
      options[:data] = data if data
      options[:filename] ||= if TSV::Parser === file
                             file.options[:filename]
                           elsif Path === file
                             file
                           elsif file.respond_to?(:filename)
                             file.filename
                           elsif Path.is_filename?(file)
                             file
                           else
                             nil
                           end

      if data
        Log.debug "TSV open #{Log.fingerprint file} into #{Log.fingerprint data}"
      else
        Log.debug "TSV open #{Log.fingerprint file}"
      end

      tsv = if TSV::Parser === file
        TSV.parse(file, **options)
      else
        options[:tsv_invert_grep] ||= invert_grep if invert_grep
        Open.open(file, grep: grep, invert_grep: invert_grep, fixed_grep: fixed_grep, nocache: nocache) do |f|
          TSV.parse(f, **options)
        end
      end

      tsv
    end
  end

  def to_hash
    self.dup
  end
end

