require 'scout/persist'
require_relative 'persist/adapter'

begin
  require_relative 'persist/tokyocabinet'
rescue Exception
end

begin
  require_relative 'persist/tkrzw'
rescue Exception
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

module Persist
  def self.persist_tsv(file, filename = nil, options = {}, persist_options = {})
    engine = IndiferentHash.process_options persist_options, :engine, engine: "HDB"
    other_options = IndiferentHash.pull_keys persist_options, :other
    other_options[:original_options] = options
    Persist.persist(file, engine, persist_options.merge(:other => other_options)) do |filename|
      if filename
        data = Persist.open_tokyocabinet(filename, true, nil, engine)
        yield(data)
        data.save_annotation_hash
        data
      else
        yield({})
      end
    end
  end
end
