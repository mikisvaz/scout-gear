require_relative 'meta_extension'
require_relative 'path/find'
require_relative 'path/util'

module Path
  extend MetaExtension
  extension_attr :pkgdir, :libdir, :path_maps

  def self.caller_lib_dir(file = nil, relative_to = ['lib', 'bin'])
    
    if file.nil?
      caller_dup = caller.dup
      while file = caller_dup.shift
        break unless file =~ /(?:scout|rbbt)\/(?:resource\.rb|workflow\.rb)/ or
          file =~ /(?:scout|rbbt)\/(?:.*\/)?path\.rb/ or
          file =~ /(?:scout|rbbt)\/(?:.*\/)?path\/(?:find|refactor|util)\.rb/ or
          file =~ /(?:scout|rbbt)\/persist.rb/
      end
      file = file.sub(/\.rb[^\w].*/,'.rb')
    end

    relative_to = [relative_to] unless Array === relative_to
    file = File.expand_path(file)
    return Path.setup(file) if relative_to.select{|d| File.exist? File.join(file, d)}.any?

    while file != '/'
      dir = File.dirname file

      return dir if relative_to.select{|d| File.exist? File.join(dir, d)}.any?

      file = File.dirname file
    end

    return nil
  end

  def self.default_pkgdir
    @@default_pkgdir ||= 'scout'
  end
  
  def self.default_pkgdir=(pkgdir)
    @@default_pkgdir = pkgdir
  end


  def pkgdir
    @pkgdir ||= Path.default_pkgdir
  end

  def libdir
    @libdir
  end

  def join(subpath, prevpath = nil)
    subpath = subpath.to_s if Symbol === subpath
    prevpath = prevpath.to_s if Symbol === prevpath

    subpath = File.join(prevpath.to_s, subpath) if prevpath
    new = self.empty? ? subpath : File.join(self, subpath)
    self.annotate(new)
    new
  end

  alias [] join
  alias / join

  def method_missing(name, prev = nil, *args, &block)
    if block_given? || name.to_s.start_with?('to_')
      super name, prev, *args, &block
    else
      join(name, prev)
    end
  end

end
