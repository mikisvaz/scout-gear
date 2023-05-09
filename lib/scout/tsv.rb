require_relative 'meta_extension'
require_relative 'tsv/util'
require_relative 'tsv/parser'
require_relative 'tsv/dumper'
require_relative 'tsv/persist'
require_relative 'tsv/index'
require_relative 'tsv/path'
require_relative 'tsv/traverse'

module TSV
  extend MetaExtension
  extension_attr :key_field, :fields, :type, :filename, :namespace, :unnamed

  def self.open(file, options = {})
    persist, type = IndiferentHash.process_options options, :persist, :persist_type, :persist => false, :persist_type => "HDB"
    Persist.persist(file, type, options.merge(:persist => persist)) do |filename|
      data = filename ? ScoutCabinet.open(filename, true, type) : nil
      options[:data] = data if data
      options[:filename] = file
      Open.open(file) do |f|
        TSV.parse(f, **options)
      end
    end
  end

end

