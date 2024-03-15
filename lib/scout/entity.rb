require 'scout/meta_extension'
require_relative 'entity/format'
require_relative 'entity/property'
require_relative 'entity/object'
require_relative 'entity/identifiers'
module Entity
  class << self
    attr_accessor :entity_property_cache, :all_formats
  end

  def self.extended(base)
    base.extend MetaExtension
    base.extend Entity::Property
    base.instance_variable_set(:@properties, [])
    base.instance_variable_set(:@persisted_methods, {})
    base.include Entity::Object
    base.include ExtendedArray
    base
  end
end
