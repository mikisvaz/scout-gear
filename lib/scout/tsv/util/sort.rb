module TSV
  def sort_by(field = nil, just_keys = false, &block)
    field = :all if field.nil?

    if field == :all
      elems = collect
    else
      elems = []
      case type
      when :single
        through :key, field do |key, field|
          elems << [key, field]
        end
      when :list, :flat
        through :key, field do |key, fields|
          elems << [key, fields.first]
        end
      when :double
        through :key, field do |key, fields|
          elems << [key, fields.first]
        end
      end
    end

    if not block_given?
      if fields == :all
        if just_keys
          keys = elems.sort_by{|key, value| key }.collect{|key, values| key}
          keys = prepare_entity(keys, key_field, entity_options.merge(:dup_array => true))
        else
          elems.sort_by{|key, value| key }
        end
      else
        sorted = elems.sort do |a, b| 
          a_value = a.last
          b_value = b.last
          a_empty = a_value.nil? or (a_value.respond_to?(:empty?) and a_value.empty?)
          b_empty = b_value.nil? or (b_value.respond_to?(:empty?) and b_value.empty?)
          case
          when (a_empty and b_empty)
            0
          when a_empty
            -1
          when b_empty
            1
          when Array === a_value
            if a_value.length == 1 and b_value.length == 1
              a_value.first <=> b_value.first
            else
              a_value.length <=> b_value.length
            end
          else
            a_value <=> b_value
          end
        end
        if just_keys
          keys = sorted.collect{|key, value| key}
          keys = prepare_entity(keys, key_field, entity_options.merge(:dup_array => true)) unless @unnamed
          keys
        else
          sorted.collect{|key, value| [key, self[key]]}
        end
      end
    else
      if just_keys
        keys = elems.sort_by(&block).collect{|key, value| key}
        keys = prepare_entity(keys, key_field, entity_options.merge(:dup_array => true)) unless @unnamed
        keys
      else
        elems.sort_by(&block).collect{|key, value| [key, self[key]]}
      end
    end
  end

  def sort(field = nil, just_keys = false, &block)
    field = :all if field.nil?

    if field == :all
      elems = collect
    else
      elems = []
      case type
      when :single
        through :key, field do |key, field|
          elems << [key, field]
        end
      when :list, :flat
        through :key, field do |key, fields|
          elems << [key, fields.first]
        end
      when :double
        through :key, field do |key, fields|
          elems << [key, fields.first]
        end
      end
    end

    if not block_given?
      if fields == :all
        if just_keys
          keys = elems.sort_by{|key, value| key }.collect{|key, values| key}
          keys = prepare_entity(keys, key_field, entity_options.merge(:dup_array => true))
        else
          elems.sort_by{|key, value| key }
        end
      else
        sorted = elems.sort do |a, b| 
          a_value = a.last
          b_value = b.last
          a_empty = a_value.nil? or (a_value.respond_to?(:empty?) and a_value.empty?)
          b_empty = b_value.nil? or (b_value.respond_to?(:empty?) and b_value.empty?)
          case
          when (a_empty and b_empty)
            0
          when a_empty
            -1
          when b_empty
            1
          when Array === a_value
            if a_value.length == 1 and b_value.length == 1
              a_value.first <=> b_value.first
            else
              a_value.length <=> b_value.length
            end
          else
            a_value <=> b_value
          end
        end
        if just_keys
          keys = sorted.collect{|key, value| key}
          keys = prepare_entity(keys, key_field, entity_options.merge(:dup_array => true)) unless @unnamed
          keys
        else
          sorted.collect{|key, value| [key, self[key]]}
        end
      end
    else
      if just_keys
        keys = elems.sort(&block).collect{|key, value| key}
        keys = prepare_entity(keys, key_field, entity_options.merge(:dup_array => true)) unless @unnamed
        keys
      else
        elems.sort(&block).collect{|key, value| [key, self[key]]}
      end
    end
  end

  def page(pnum, psize, field = nil, just_keys = false, reverse = false, &block)
    pstart = psize * (pnum - 1)
    pend = psize * pnum - 1
    field = :key if field == "key"
    keys = sort_by(field || :key, true, &block)
    keys.reverse! if reverse

    if just_keys
      keys[pstart..pend]
    else
      select :key => keys[pstart..pend]
    end
  end

end
