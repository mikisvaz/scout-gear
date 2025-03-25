require 'scout/annotation'
module Association

  def self.index(file, source: nil, target: nil, source_format: nil, target_format: nil, format: nil, database: nil, **kwargs)
    IndiferentHash.setup(kwargs)
    source = kwargs.delete :source if kwargs.include?(:source)
    target = kwargs.delete :target if kwargs.include?(:target)

    persist_options = IndiferentHash.pull_keys kwargs, :persist
    index_persist_options = IndiferentHash.add_defaults persist_options.dup, persist: true, 
      prefix: "Association::Index", 
      other_options: kwargs.merge(source: source, target: target, source_format: source_format, target_format: target_format, format: format)

    index = Persist.tsv(file, kwargs, engine: "BDB", persist_options: index_persist_options) do |data|
      recycle, undirected = IndiferentHash.process_options kwargs, :recycle, :undirected

      database ||= Association.open(file, source: source, target: target, source_format: source_format, target_format: target_format, **kwargs.merge(persist_prefix: "Association::Database"))

      source_field = database.key_field
      target_field, *fields = database.fields

      undirected = true if undirected.nil? and source_field == target_field

      key_field = [source_field, target_field, undirected ? "undirected" : nil].compact * "~"

      dumper = TSV::Dumper.new database.options.merge(key_field: key_field, fields: fields, type: :list)
      transformer = TSV::Transformer.new database, dumper

      if database.type == :double
        transformer.traverse do |source,value_list|
          res = []
          NamedArray.zip_fields(value_list).collect do |values|
            target, *info = values
            key = [source, target] * "~"
            res << [key, info]
            if undirected
              key = [target, source] * "~"
              res << [key, info]
            end
          end
          res.extend MultipleResult
        end
      elsif database.type == :flat
        transformer.traverse do |source,targets|
          res = []
          res.extend MultipleResult
          targets.each do |target|
            key = [source, target] * "~"
            res << [key, []]
            if undirected
              key = [target, source] * "~"
              res << [key, []]
            end
          end
          res
        end
      else
        transformer.traverse do |source,values|
          res = []
          res.extend MultipleResult
          target, *info = values
          key = [source, target] * "~"
          res << [key, info]
          if undirected
            key = [target, source] * "~"
            res << [key, info]
          end
          res
        end
      end

      tsv = transformer.tsv **kwargs.merge(data: data, fields: fields)
    end
    index.extend Index
    index.parse_key_field
    index
  end

  module Index
    extend Annotation

    annotation :source_field, :target_field, :undirected

    def parse_key_field
      @source_field, @target_field, @undirected = key_field.split("~")
    end

    def match(entity)
      return entity.inject([]){|acc,e| acc.concat match(e); acc } if Array === entity
      return [] if entity.nil?
      prefix(entity + "~")
    end

    def subset(source, target)
      return [] if source.nil? or target.nil? or source.empty? or target.empty?

      if source == :all or source == "all"
        if target == :all or target == "all"
          return keys
        else
          matches = reverse.subset(target, source)
          return matches.collect{|m| r = m.partition "~"; r.reverse*"" }
        end
      end

      matches = source.uniq.inject([]){|acc,e| 
        if block_given?
          acc.concat(match(e))
        else
          acc.concat(match(e))
        end
      }

      return matches if target == :all or target == "all"

      target_matches = {}

      matches.each{|code| 
        s,sep,t = code.partition "~"
        next if undirected and t > s and source.include? t
        target_matches[t] ||= []
        target_matches[t] << code
      }

      target_matches.values_at(*target.uniq).flatten.compact
    end

    def reverse
      @reverse ||= begin
                     if self.respond_to? :persistence_path
                       persistence_path = self.persistence_path
                       persistence_path = persistence_path.find if Path === persistence_path
                       reverse_filename = persistence_path + '.reverse'
                     else
                       raise "Can only reverse a TokyoCabinet::BDB dataset at the time"
                     end

                     if Open.exist?(reverse_filename)
                       new = Persist.open_tokyocabinet(reverse_filename, false, serializer, TokyoCabinet::BDB)
                       raise "Index has no info: #{reverse_filename}" if new.key_field.nil?
                       new.extend Index
                       new
                     else
                       Open.mkdir File.dirname(reverse_filename) unless Open.exist?(File.dirname(reverse_filename))

                       new = Persist.open_tokyocabinet(reverse_filename, true, serializer, TokyoCabinet::BDB)

                       self.with_unnamed do
                         self.traverse do |key, value|
                           new_key = key.split("~").reverse.join("~")
                           new[new_key] = value
                         end
                       end
                       annotate(new)
                       new.key_field = key_field.split("~").values_at(1,0,2).compact * "~"
                       new.save_annotation_hash
                       new.read_and_close do
                         Association::Index.setup new
                       end
                       new.parse_key_field
                       new.read
                     end

                     new.unnamed = self.unnamed

                     new.undirected = undirected

                     new
                   rescue Exception
                     Log.error "Deleting after error reversing database: #{ reverse_filename }"
                     FileUtils.rm reverse_filename if File.exist? reverse_filename
                     raise $!
                   end
    end

    def filter(value_field = nil, target_value = nil, &block)
      if block_given?
        matches = []
        if value_field
          through :key, value_field do |key,values|
            pass = block.call values
            matches << key if pass
          end
        else
          through do |key,values|
            pass = block.call [key, values]
            matches << key if pass
          end
        end
        matches

      else
        matches = []
        if target_value
          target_value = [target_value] unless Array === target_value
          through :key, value_field do |key,values|
            pass = (values & target_value).any?
            matches << key if pass
          end
        else
          through :key, value_field do |key,values|
            pass = false
            values.each do |value|
              pass = true unless value.nil? or value.empty? or value.downcase == 'false'
            end
            matches << key if pass
          end
        end
        matches
      end
    end

    def to_matrix(value_field = nil, &block)
      value_field = fields.first if value_field.nil? and fields.length == 1
      value_pos = identify_field value_field if value_field and String === value_field
      key_field = source_field

      tsv = if value_pos
              AssociationItem.incidence self.keys, key_field do |key|
                if block_given? 
                  yield self[key][value_pos]
                else
                  self[key][value_pos]
                end
              end
            elsif block_given?
              AssociationItem.incidence self.keys, key_field, &block
            else
              AssociationItem.incidence self.keys, key_field 
            end
    end
  end
end
