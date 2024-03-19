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

  def self.prepare_entity(entity, field, options = {})
    return entity unless defined? Entity
    return entity unless String === entity or Array === entity
    options ||= {}

    dup_array = options.delete :dup_array

    if Entity === field or (Entity.respond_to?(:formats) and (_format = Entity.formats.find(field)))
      params = options.dup

      params[:format] ||= params.delete "format"
      params.merge!(:format => _format) unless _format.nil? or (params.include?(:format) and not ((f = params[:format]).nil? or (String === f and f.empty?)))

      mod = Entity === field ? field : Entity.formats[field]

      entity = entity.dup
      entity = (entity.frozen? and not entity.nil?) ? entity.dup : ((Array === entity and dup_array) ? entity.collect{|e| e.nil? ? e : e.dup} : entity) 

      entity = mod.setup(entity, params)
    end

    entity
  end
end
