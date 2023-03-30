require_relative '../indiferent_hash'
module Path

  def _parts
    @_parts ||= self.split("/")
  end

  def _subpath
    @subpath ||= _parts.length > 1 ? _parts[1..-1] * "/" : _parts[0] || ""
  end
  
  def _toplevel
    @toplevel ||= _parts.length > 1 ? _parts[0] : ""
  end

  def self.follow(path, map)
    map.sub('{PKGDIR}', path.pkgdir.respond_to?(:subdir) ? path.pkgdir.pkgdir : path.pkgdir || Path.default_pkgdir).
      sub('{RESOURCE}', path.pkgdir.to_s).
      sub('{PWD}', FileUtils.pwd).
      sub('{TOPLEVEL}', path._toplevel).
      sub('{SUBPATH}', path._subpath).
      sub('{BASENAME}', File.basename(path)).
      sub('{PATH}', path).
      sub('{LIBDIR}', path.libdir || (path.pkgdir.respond_to?(:libdir) && path.pkgdir.libdir) || Path.caller_lib_dir).
      sub('{REMOVE}/', '').
      sub('{REMOVE}', '').gsub(/\/+/,'/')
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

  def self.map_search
    @@map_search ||= %w(current workflow user local global lib fast cache bulk)
  end

  def self.search_order
    @@search_order ||= (path_maps.keys & map_search) + (path_maps.keys - map_search)
  end

  def self.add_path(name, map)
    @@path_maps[name] = map
    @@search_order = nil
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

  def follow(map_name = :default, annotate = true)
    map = Path.path_maps[map_name]
    while Symbol === map
      map_name = map
      map = Path.path_maps[map_name]
    end
    found = Path.follow(self, map)

    annotate_found_where(found, map_name)  if annotate

    found
  end

  def find(where = nil)
    return self if located?
    return find_all if where == 'all' || where == :all
    return follow(where) if where

    Path.search_order.each do |map_name|
      found = follow(map_name, false)

      return annotate_found_where(found, map_name) if File.exist?(found) || File.directory?(found)
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
    Path.search_order
      .collect{|where| find(where) }
      .select{|file| file.exist? }.uniq
  end
end
