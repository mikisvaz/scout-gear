module Entity
  class << self
    attr_accessor :entity_property_cache

    def entity_property_cache
      @entity_property_cache ||= Path.setup('var/entity_property')
    end
  end

  module Property
    attr_accessor :persisted_methods, :properties

    def self.single_method(name)
      ("_single_" + name.to_s).to_sym
    end
     
    def self.array_method(name)
      ("_ary_" + name.to_s).to_sym
    end

    def self.multi_method(name)
      ("_multi_" + name.to_s).to_sym
    end

    DEFAULT_PROPERTY_TYPE = :both
    def property(name_and_type, &block)
      name, type = case name_and_type
                   when Symbol, String
                     [name_and_type.to_sym, DEFAULT_PROPERTY_TYPE]
                   else
                     name_and_type.collect.first
                   end

      real_method = case type
                    when :single, :single2array
                      Entity::Property.single_method(name)
                    when :array, :array2single
                      Entity::Property.array_method(name)
                    when :multiple
                      Entity::Property.multi_method(name)
                    when :both
                      name
                    else
                      raise "Type of property unknown #{type}"
                    end

      properties.push name


      entity_class = self
      if type == :multiple
        self.define_method(real_method) do |*args,**kwargs|
          if entity_class.persisted_methods && entity_class.persisted_methods[name]
            type, options = entity_class.persisted_methods[name]
          else
            type, options = nil, {persist: false}
          end

          missing = []
          responses = {}
          self.each do |item|
            begin
              responses[item] = Persist.persist("#{entity_class} property #{real_method} - #{Misc.digest([item, item.annotations])}", type, options) do
                raise 
              end
            rescue
              missing << item
            end
          end

          self.annotate(missing)

          new_responses = missing.instance_exec(*args, **kwargs, &block)

          missing.each do |item,i|
            responses[item] = Persist.persist("#{entity_class} property #{real_method} - #{Misc.digest([item, item.annotations])}", type, options) do
              Array === new_responses ? new_responses[item.container_index] : new_responses[item]
            end
          end

          responses.values_at(*self)
        end
      else
        self.define_method(real_method) do |*args,**kwargs|
          if entity_class.persisted_methods && entity_class.persisted_methods[name]
            type, options = entity_class.persisted_methods[name]
          else
            type, options = nil, {persist: false}
          end

          Persist.persist([name, self.id] * ":", type, options) do
            self.instance_exec(*args, **kwargs, &block)
          end
        end
      end

      return if type == :both

      self.define_method(name) do |*args,**kwargs|

        method_type = %w(single_method array_method multi_method).select do |method_type|
          self.methods.include?(Entity::Property.send(method_type, name))
        end.first

        real_method = Entity::Property.send(method_type, name)

        if Array === self
          case method_type
          when 'single_method'
            self.collect{|item| item.send(real_method, *args, **kwargs) }
          when 'array_method', 'multi_method'
            self.send(real_method, *args, **kwargs)
          end
        else
          case method_type
          when 'single_method'
            self.send(real_method, *args, **kwargs)
          when 'array_method', 'multi_method'
            if AnnotatedArray.is_contained?(self)
              cache_code = Misc.digest({:name => name, :args => args})
              res = (self.container._ary_property_cache[cache_code] ||= self.container.send(real_method, *args, **kwargs))
              Array === res ? res[self.container_index] : res[self]
            else
              res = self.make_array.send(real_method)
              Array === res ? res[0] : res[self]
            end
          end
        end
      end
    end

    def persist(name, type = :marshal, options = {})
      options = IndiferentHash.add_defaults options, persist: true, dir: File.join(Entity.entity_property_cache, self.to_s, name.to_s)
      @persisted_methods ||= {}
      @persisted_methods[name] = [type, options]
    end

    def persisted?(name)
      @persisted_methods ||= {}
      @persisted_methods.include?(name)
    end

    def unpersist(name)
      @persisted_methods ||= {}
      @persisted_methods.delete(name)
    end
  end
end
