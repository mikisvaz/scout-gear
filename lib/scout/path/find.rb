module Path
  def _parts
    @_parts ||= self.split("/")
  end

  def _subpath
    @subpath ||= _parts.length > 1 ? _parts[1..-1] * "/" : _parts[0]
  end
  
  def _toplevel
    @toplevel ||= _parts.length > 1 ? _parts[0] : nil
  end

  def self.follow(path, map)
    map.sub('{PKGDIR}', path.namespace).
      sub('{NAMESPACE}', path.namespace).
      sub('{RESOURCE}', path.to_s).
      sub('{PWD}', FileUtils.pwd).
      sub('{TOPLEVEL}', path._toplevel).
      sub('{SUBPATH}', path._subpath).
      sub('{BASENAME}', File.basename(path)).
      sub('{PATH}', path).
      sub('{LIBDIR}', path.libdir).
      sub('{REMOVE}/', '').
      sub('{REMOVE}', '').gsub(/\/+/,'/')
  end

  PATH_MAPS = IndiferentHash.setup({
    :current => File.join("{PWD}", "{TOPLEVEL}", "{SUBPATH}"),
    :user    => File.join(ENV['HOME'], ".{PKGDIR}", "{TOPLEVEL}", "{SUBPATH}"),
    :global  => File.join('/', "{TOPLEVEL}", "{PKGDIR}", "{SUBPATH}"),
    :usr   => File.join('/usr/', "{TOPLEVEL}", "{PKGDIR}", "{SUBPATH}"),
    :local   => File.join('/usr/local', "{TOPLEVEL}", "{PKGDIR}", "{SUBPATH}"),
    :fast   => File.join('/fast', "{TOPLEVEL}", "{PKGDIR}", "{SUBPATH}"),
    :cache   => File.join('/cache', "{TOPLEVEL}", "{PKGDIR}", "{SUBPATH}"),
    :bulk   => File.join('/bulk', "{TOPLEVEL}", "{PKGDIR}", "{SUBPATH}"),
    :lib     => File.join('{LIBDIR}', "{TOPLEVEL}", "{SUBPATH}"),
    :base   => File.join(Path.caller_lib_dir(__FILE__), "{TOPLEVEL}", "{SUBPATH}"),
    :default => :user
  })

  MAP_SEARCH = %w(current workflow user local global lib fast cache bulk)

  def _follow(map_name)
    map = PATH_MAPS[map_name]
    while Symbol === map
      map = PATH_MAPS[map]
    end
    Path.follow(self, map)
  end

  def find(where = nil)
    return _follow(where) if where

    all_maps = PATH_MAPS.keys
    search_order = MAP_SEARCH & all_maps + (all_maps - MAP_SEARCH)

    search_order.each do |name|
      map = PATH_MAPS[name]
      real_path = _follow(map)
      return real_path if File.exists?(real_path)
    end

    return _follow(:default)
  end
end
