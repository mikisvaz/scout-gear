require 'scout-essentials'
require_relative 'scout/tsv'

Path.path_maps[:scout_gear] = File.join(Path.caller_lib_dir(__FILE__), "{TOPLEVEL}/{SUBPATH}")

Persist.cache_dir     = Scout.var.cache.persistence
TmpFile.tmpdir        = Scout.tmp.find :user
Resource.default_resource = Scout

