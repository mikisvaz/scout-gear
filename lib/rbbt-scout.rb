$LOAD_PATH.unshift File.join(__dir__, '../modules/rbbt-util/lib')
module Scout
  extend Resource
  self.path_maps = Path.path_maps.merge(:rbbt_lib => File.expand_path(File.join(__dir__, '../modules/rbbt-util/', '{TOPLEVEL}','{SUBPATH}')))
end
Rbbt = Scout

Resource.set_software_env Rbbt.software
