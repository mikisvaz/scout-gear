module Entity
  def self.extended(base)
    meta = class << base; self end
    base.extend MetaExtension

    meta.define_method(:property) do |name,&block|
      self.define_method(name, &block)
    end
  end
end
