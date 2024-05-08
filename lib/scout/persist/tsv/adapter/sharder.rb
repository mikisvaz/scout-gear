require_relative 'base'
require_relative '../../engine/sharder'
 
module ShardAdapter
  include TSVAdapter

  def self.extended(obj)
    obj.extend TSVAdapter
    class << obj
      alias keys orig_keys
      alias each orig_each
    end
  
    obj
  end

  def metadata_file
    @metadata_file ||= File.join(self.persistence_path, 'metadata')
  end

  def load_annotation_hash
    ANNOTATION_ATTR_HASH_SERIALIZER.load(Open.read(metadata_file, mode: 'rb'))
  end

  def save_annotation_hash
    Open.write(metadata_file, ANNOTATION_ATTR_HASH_SERIALIZER.dump(self.annotation_hash), mode: 'wb')
  end

  def size
    databases.values.inject(0){|acc,d| acc += d.size }
  end

  def keys
    databases.values.inject([]){|acc,d| acc.concat(d.keys); acc }
  end

  def prefix(...)
    databases.values.inject([]){|acc,d| acc.concat(d.prefix(...)); acc }
  end

  def include?(key)
    self[key] != nil
  end
end

module Persist
  def self.open_sharder(persistence_path, write=false, db_type=nil, persist_options={}, &block)
    database = Sharder.new(persistence_path, write, db_type, persist_options, &block)
    database.extend ShardAdapter
    database.serializer = TSVAdapter.serializer_module(persist_options[:serializer]) if persist_options[:serializer]
    database.save_annotation_hash
    database
  end
end
