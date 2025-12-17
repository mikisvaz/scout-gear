require_relative 'base'
require_relative '../../engine/tkrzw'

Persist.save_drivers[:tkh] = proc do |file, content|
  data = ScoutTKRZW.open(file, true, "tkh")
  content.annotate(data)
  data.extend TSVAdapter
  data.merge!(content)
  data.close
  data.read
  data
end

Persist.load_drivers[:tkh] = proc do |file|
  data = ScoutTKRZW.open(file, false, "tkh")
  data.extend TSVAdapter unless TSVAdapter === data
  data
end
