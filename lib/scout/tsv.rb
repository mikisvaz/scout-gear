require_relative 'meta_extension'
require_relative 'tsv/parser'

module TSV
  extend MetaExtension
  extension_attr :key_field, :fields

  def self.open(file, options = {})
    Open.open(file) do |f|
      TSV.parse(f,**options)
    end
  end
end

