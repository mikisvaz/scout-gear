module Entity
  class FormatIndex < Hash

    alias orig_include? include?

    def initialize
      @find_cache = {}
    end

    def find(value)
      @find_cache ||= {}

      @find_cache[value] ||= begin
                               if orig_include? value
                                 @find_cache[value] = value
                               else
                                 found = nil
                                 each do |k,v|
                                   if value.to_s == k.to_s
                                     found = k
                                     break
                                   elsif value.to_s =~ /\(#{Regexp.quote k}\)/
                                     found = k
                                     break
                                   end
                                 end
                                 found
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
