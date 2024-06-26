class PackedIndex
  attr_accessor :persistence_path, :mask, :mask_length, :offset, :item_size, :stream, :nil_string

  ELEMS = {
    "i" => ["l", 4],
    "I" => ["q", 8],
    "f" => ["f", 4],
    "F" => ["d", 8],
  }

  def self.process_mask(mask)
    str = ""
    size = 0
    mask.each do |e|
      if ELEMS.include? e
        str << ELEMS[e][0]
        size += ELEMS[e][1]
      elsif e =~ /^(\d+)s$/
        num = $1.to_i
        str << "a" << num.to_s
        size += num
      else
        e, num = e.split(":")
        str << e
        size = (num.nil? ? size + 1 : size + num.to_i)
      end
    end
    [str, size]
  end

  def size
    @size ||= begin
                (File.size(persistence_path) - offset) / item_size
              end
  end

  def initialize(persistence_path, write = false, pattern = nil)
    @persistence_path = persistence_path
    if write
      @stream = Open.open(persistence_path, :mode => 'wb')
      @mask, @item_size = PackedIndex.process_mask pattern
      header = [@mask.length, @item_size].pack("ll")
      @stream.write(header)
      @stream.write(mask)
      @offset = @mask.length + 8
    else
      @stream = Open.open(persistence_path, :mode => 'rb')
      header = @stream.read(8)
      mask_length, @item_size = header.unpack("ll")
      @mask = @stream.read(mask_length)
      @offset = @mask.length + 8
    end
    @nil_string = "NIL" << ("-" * (@item_size - 3))
  end

  def file
    @persistence_path
  end
  
  def close
    @stream.close
  end

  def write(force = false)
    close
    @stream = Open.open(persistence_path, :mode => 'wb')
  end

  def read(force = false)
    close
    @stream = Open.open(persistence_path, :mode => 'rb')
  end

  def <<(payload)
    if payload.nil?
      @stream.write nil_string
    else
      @stream.write payload.pack(mask)
    end
  end

  def get_position(position)
    @stream.seek(position * item_size + offset)
    encoded = @stream.read(item_size)
    return nil if encoded.nil? or encoded == nil_string 
    encoded.unpack mask
  end

  alias [] get_position

  def values_at(*positions)
    positions.collect{|p|
      get_position[p]
    }
  end

  def close
    @stream.close unless @stream.closed?
  end
end
