require 'scout-essentials'
require_relative 'scout/tsv'
require_relative 'scout/offsite'

Path.path_maps[:scout_gear] = File.join(Path.caller_lib_dir(__FILE__), "{TOPLEVEL}/{SUBPATH}")
