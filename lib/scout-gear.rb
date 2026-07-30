require 'scout-essentials'
require_relative 'scout/tsv'

Path.path_maps[:scout_gear_lib] = File.join(Path.caller_lib_dir(__FILE__), "{TOPLEVEL}/{SUBPATH}")

Resource.default_resource = Scout
Persist.cache_dir     = Path.setup('var').cache.persistence
TmpFile.tmpdir        = Path.setup('tmp').find :user
