module Entity
  module Object

    def entity_classes
      annotation_types.select{|t| Entity === t}
    end

    def base_entity
      entity_classes.last
    end

    def _ary_property_cache
      @_ary_property_cache ||= {}
    end

    def all_properties
      entity_classes.inject([]){|acc,e| acc.concat(e.properties.keys) }
    end
  end
end
