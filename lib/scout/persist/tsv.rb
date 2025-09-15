require 'scout/persist'
require_relative 'engine'
require_relative 'tsv/adapter'

Persist.save_drivers[:tsv] = proc do |file,content| 
  case content
  when IO
    Open.sensible_write(file, content)
  when TSV
    Open.sensible_write(file, content)
  else
    stream = if content.respond_to?(:stream)
               content.stream
             elsif content.respond_to?(:dumper_stream)
               content.dumper_stream
             else
               content
             end
    Open.sensible_write(file, stream)
  end
end

Persist.load_drivers[:tsv] = proc do |file| TSV.open file end

module Persist

  def self.open_database(path, write, serializer = nil, type = "HDB", options = {})
    db = case type
         when 'fwt'
           value_size, range, update, in_memory, pos_function = IndiferentHash.process_options options.dup, :value_size, :range, :update, :in_memory, :pos_function
           if pos_function
             Persist.open_fwt(path, value_size, range, serializer, update, in_memory, &pos_function)
           else
             Persist.open_fwt(path, value_size, range, serializer, update, in_memory)
           end
         when 'pki'
           pattern, pos_function = IndiferentHash.process_options options.dup, :pattern, :pos_function
           if pos_function
             Persist.open_pki(path, write, pattern, &pos_function)
           else
             Persist.open_pki(path, write, pattern)
           end
         else
           Persist.open_tokyocabinet(path, write, serializer, type)
         end
    db
  end

  def self.tsv(id, options = {}, engine: nil, persist_options: {})
    engine ||= persist_options[:engine] || :HDB
    persist_options[:other_options] = options unless persist_options.include?(:other_options)
    Persist.persist(id, engine, persist_options) do |filename|
      if filename.nil?
        yield(persist_options[:data] || {})
      else
        if persist_options.include?(:shard_function)
          data = persist_options[:data] ||= Persist.open_sharder(filename, true, engine, options.merge(persist_options), &persist_options[:shard_function])
        else
          data = persist_options[:data] ||= Persist.open_database(filename, true, persist_options[:serializer], engine, options)
        end

        data.serializer = TSVAdapter.serializer_module(persist_options[:serializer]) if persist_options[:serializer]

        yield(data)
        data.save_annotation_hash if Annotation.is_annotated?(data)
        data.read if data.respond_to?(:read)
        data
      end
    end
  end

  def self.persist_tsv(file, filename = nil, options = {}, persist_options = {}, &block)
    persist_options = IndiferentHash.add_defaults persist_options,
      IndiferentHash.pull_keys(options, :persist)

    persist_options[:data] ||= options.delete(:data)
    engine = IndiferentHash.process_options persist_options, :engine, engine: "HDB"
    other_options = IndiferentHash.pull_keys persist_options, :other
    other_options[:original_options] = options

    Persist.tsv(file, engine: engine, persist_options: persist_options.merge(other: other_options), &block)
  end

  #def self.persist_tsv(file, filename = nil, options = {}, persist_options = {})
  #  persist_options = IndiferentHash.add_defaults persist_options,
  #    IndiferentHash.pull_keys(options, :persist)

  #  persist_options[:data] ||= options.delete(:data)
  #  engine = IndiferentHash.process_options persist_options, :engine, engine: "HDB"
  #  other_options = IndiferentHash.pull_keys persist_options, :other
  #  other_options[:original_options] = options
  #  Persist.persist(file, engine, persist_options.merge(:other => other_options)) do |filename|
  #    if filename
  #      if persist_options.include?(:shard_function)
  #        data = persist_options[:data] ||= Persist.open_sharder(filename, true, engine, options.merge(persist_options), &persist_options[:shard_function])
  #      else
  #        data = persist_options[:data] ||= Persist.open_database(filename, true, persist_options[:serializer], engine, options)
  #      end


  #      yield(data)
  #      data.save_annotation_hash if Annotation.is_annotated?(data)
  #      data
  #    else
  #      yield(persist_options[:data] || {})
  #    end
  #  end
  #end
end
