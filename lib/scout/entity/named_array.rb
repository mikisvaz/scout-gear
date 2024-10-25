require 'scout/named_array'
require 'scout/entity'

module NamedArray

  def [](key)
    pos = NamedArray.identify_name(@fields, key)
    return nil if pos.nil?
    v = super(pos)
    field = @fields && Integer === key && ! @fields.include?(key) ? @fields[key] : key
    Entity.prepare_entity(v, field)
  end
end
