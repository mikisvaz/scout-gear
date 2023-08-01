require 'scout/persist'
require_relative 'persist/adapter'

begin
  require_relative 'persist/tokyocabinet'
rescue
end

begin
  require_relative 'persist/tkrzw'
rescue
end

Persist.save_drivers[:tsv] = proc do |file,content| 
  stream = if IO === content
             content
           elsif content.respond_to?(:stream)
             content.stream
           elsif content.respond_to?(:dumper_stream)
             content.dumper_stream
           else
             content
           end
  Open.sensible_write(file, stream)
end

Persist.load_drivers[:tsv] = proc do |file| TSV.open file end
