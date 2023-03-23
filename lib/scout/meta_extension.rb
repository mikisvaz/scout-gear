module MetaExtension
  def self.extended(base)
    meta = class << base; self; end

    base.class_variable_set("@@extension_attrs", [])

    meta.define_method(:extension_attr) do |*attrs|
      self.class_variable_get("@@extension_attrs").concat attrs
      attrs.each do |a|
        self.attr_accessor a
      end
    end

    meta.define_method(:setup) do |obj,*rest|
      obj.extend base
      self.class_variable_get("@@extension_attrs").zip(rest).each do |name,value|
        obj.instance_variable_set("@#{name}", value)
      end
      obj
    end

    base.define_method(:annotate) do |other|
      attr_values = meta.class_variable_get("@@extension_attrs").collect do |a|
        self.instance_variable_get("@#{a}")
      end
      base.setup(other, *attr_values)
    end
  end
end
