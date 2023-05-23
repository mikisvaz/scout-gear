module Misc
  def self.digest_str(obj)
    if obj.respond_to?(:digest_str)
      obj.digest_str
    else
      case obj
      when String
        #'\'' << obj << '\''
        if Path === obj || ! Open.exists?(obj)
          '\'' << obj << '\''
        else
          Misc.file_md5(obj)
        end
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
      when TrueClass
        "true"
      when FalseClass
        "false"
      else
        obj.inspect
      end
    end
  end

  def self.digest(obj)
    str = String === obj ? obj : Misc.digest_str(obj)
    Digest::MD5.hexdigest(str)
  end

  def self.file_md5(file)
    file = file.find if Path === file
    #md5file = file + '.md5'
    Persist.persist("MD5:#{file}", :string) do
      Digest::MD5.file(file).hexdigest
    end
  end
end
