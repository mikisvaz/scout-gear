module Misc
  def self.digest_str(obj)
    if obj.respond_to?(:digest_str)
      str = obj.digest_str
    else
      case obj
      when String
        #'\'' << obj << '\''
        '\'' << obj << '\''
      when Integer, Symbol
        obj.to_s
      when Array
        '[' << obj.inject(""){|acc,o| acc.empty? ? Misc.digest_str(o) : acc << ', ' << Misc.digest_str(o) } << ']'
      when Hash
        '{' << obj.inject(""){|acc,p| s = Misc.digest_str(p.first) << "=" << Misc.digest_str(p.last); acc.empty? ? s : acc << ', ' << s } << '}'
      when Integer
        obj.to_s
      when Float
        if obj % 1 == 0
          obj.to_i
        elsif obj.abs > 10
          "%.1f" % obj
        elsif obj.abs > 1
          "%.3f" % obj
        else
          "%.6f" % obj
        end
      else
        obj.inspect
      end
    end
  end

  def self.digest(obj)
    str = Misc.digest_str(obj)
    Digest::MD5.hexdigest(str)
  end
end
