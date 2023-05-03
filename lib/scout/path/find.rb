require_relative '../indiferent_hash'
module Path

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

  def self.follow(path, map, map_name = nil)
    file = map.sub('{PKGDIR}', path.pkgdir.respond_to?(:pkgdir) ? path.pkgdir.pkgdir || Path.default_pkgdir : path.pkgdir || Path.default_pkgdir).
      sub('{RESOURCE}', path.pkgdir.to_s).
      sub('{PWD}', FileUtils.pwd).
      sub('{TOPLEVEL}', path._toplevel).
      sub('{SUBPATH}', path._subpath).
      sub('{BASENAME}', File.basename(path)).
      sub('{PATH}', path).
      sub('{LIBDIR}', path.libdir || (path.pkgdir.respond_to?(:libdir) && path.pkgdir.libdir) || Path.caller_lib_dir).
      sub('{MAPNAME}', map_name.to_s).
      sub('{REMOVE}/', '').
      sub('{REMOVE}', '').gsub(/\/+/,'/')

    while true
      file.gsub!(/\{(.+)(?<!\\)\/(.+)(?<!\\)\/(.+)\}/) do |m|
        key, orig, replace = m.split(/(?<!\\)\//).collect{|p| p.gsub('\/','/') }
        key_text = follow(path, "#{key}}", map_name)
        key_text[orig] = replace[0..-2] if key_text.include?(orig)
        key_text
      end || break
    end

    file
  end

  def self.path_maps
    @@path_maps ||= IndiferentHash.setup({
      :current => File.join("{PWD}", "{TOPLEVEL}", "{SUBPATH}"),
      :user    => File.join(ENV['HOME'], ".{PKGDIR}", "{TOPLEVEL}", "{SUBPATH}"),
      :global  => File.join('/', "{TOPLEVEL}", "{PKGDIR}", "{SUBPATH}"),
      :usr     => File.join('/usr/', "{TOPLEVEL}", "{PKGDIR}", "{SUBPATH}"),
      :local   => File.join('/usr/local', "{TOPLEVEL}", "{PKGDIR}", "{SUBPATH}"),
      :fast    => File.join('/fast', "{TOPLEVEL}", "{PKGDIR}", "{SUBPATH}"),
      :cache   => File.join('/cache', "{TOPLEVEL}", "{PKGDIR}", "{SUBPATH}"),
      :bulk    => File.join('/bulk', "{TOPLEVEL}", "{PKGDIR}", "{SUBPATH}"),
      :lib     => File.join('{LIBDIR}', "{TOPLEVEL}", "{SUBPATH}"),
      :base    => File.join(Path.caller_lib_dir(__FILE__), "{TOPLEVEL}", "{SUBPATH}"),
      :default => :user
    })
  end

  def self.basic_map_order
    @@basic_map_order ||= %w(current workflow user local global lib fast cache bulk)
  end

  def self.map_order
    @@map_order ||= (path_maps.keys & basic_map_order) + (path_maps.keys - basic_map_order)
  end

  def self.add_path(name, map)
    @@path_maps[name] = map
    @@map_order = nil
  end

  def _parts
    @_parts ||= self.split("/")
  end

  def _subpath
    @subpath ||= _parts.length > 1 ? _parts[1..-1] * "/" : _parts[0] || ""
  end
  
  def _toplevel
    @toplevel ||= _parts.length > 1 ? _parts[0] : ""
  end

  SLASH = "/"[0]
  DOT = "."[0]
  def located?
    # OPEN RESOURCE
    self.slice(0,1) == SLASH || (self.slice(0,1) == DOT && self.slice(1,2) == SLASH) # || (resource != Rbbt && (Open.remote?(self) || Open.ssh?(self)))
  end

  def annotate_found_where(found, where)
    self.annotate(found).tap{|p| 
      p.instance_variable_set("@where", where) 
      p.instance_variable_set("@original", self.dup) 
    }
  end

  def where
    @where
  end

  def original
    @original
  end

  def map_order
    @map_order ||= (path_maps.keys & Path.basic_map_order) + (path_maps.keys - Path.basic_map_order)
  end

  def follow(map_name = :default, annotate = true)
    IndiferentHash.setup(path_maps)
    map = path_maps[map_name] || Path.path_maps[map_name]
    raise "Map not found #{Log.fingerprint map_name} not in #{Log.fingerprint path_maps.keys}" if map.nil?
    while Symbol === map
      map_name = map
      map = path_maps[map_name]
    end
    found = Path.follow(self, map, map_name)

    annotate_found_where(found, map_name)  if annotate

    found
  end

  def self.exists_file_or_alternatives(file)
    return file if File.exist?(file) or File.directory?(file)
    %w(gz bgz zip).each do |extension|
      alt_file = file + '.' + extension
      return alt_file if File.exist?(alt_file) or File.directory?(alt_file)
    end
    nil
  end

  def find(where = nil)
    if located?
      if File.exist?(self)
        return self if located?
      else
        found = Path.exists_file_or_alternatives(self)
        if found
          return self.annotate(found)
        else
          return self if located?
        end
      end
    end

    return find_all if where == 'all' || where == :all

    return follow(where) if where

    map_order.each do |map_name|
      found = follow(map_name, false)

      found = Path.exists_file_or_alternatives(found)
      return annotate_found_where(found, map_name) if found
    end

    return follow(:default)
  end

  def exist?
    # OPEN
    found = self.find
    File.exist?(found) || File.directory?(found)
  end

  alias exists? exist?

  def find_all(caller_lib = nil, search_paths = nil)
    map_order
      .collect{|where| find(where) }
      .select{|file| file.exist? }.uniq
  end

end
