require 'scout/named_array'
require 'scout/entity'

module NamedArray

  def [](key)
    pos = NamedArray.identify_name(@fields, key)
    return nil if pos.nil?
    v = super(pos)
    Entity.prepare_entity(v, key)
  end
end
