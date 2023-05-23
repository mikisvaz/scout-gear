$LOAD_PATH.unshift File.join(__dir__, '../modules/rbbt-util/lib')
module Rbbt
  extend Resource
  self.pkgdir = 'rbbt'
  self.path_maps = Path.path_maps.merge(:rbbt_lib => File.expand_path(File.join(__dir__, '../modules/rbbt-util/', '{TOPLEVEL}','{SUBPATH}')))
end
