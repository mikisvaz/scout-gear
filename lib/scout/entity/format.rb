module Entity
  def format=(formats)
    formats = [formats] unless Array === formats
    formats.each do |format|
      Entity.formats[format] ||= self
    end
  end

  class FormatIndex < Hash

    alias orig_include? include?

    def initialize
      @find_cache = {}
    end

    def find(value)
      @find_cache ||= {}

      if @find_cache.include?(value)
        @find_cache[value]
      else
        @find_cache[value] = begin
                               if orig_include? value
                                 value
                               else
                                 value = value.to_s
                                 found = nil
                                 each do |k,v|
                                   if value == k.to_s
                                     found = k
                                     break
                                   elsif value =~ /\(#{Regexp.quote k.to_s}\)/
                                     found = k
                                     break
                                   end
                                 end
                                 found
                               end
                             end
      end
    end

    def [](value)
      res = super
      return res if res
      key = find(value)
      key ? super(key) : nil
    end

    def []=(key,value)
      @find_cache = {}
      super(key, value)
    end

    def include?(value)
      find(value) != nil
    end
  end

  FORMATS ||= FormatIndex.new

  def self.formats
    FORMATS
  end

end
