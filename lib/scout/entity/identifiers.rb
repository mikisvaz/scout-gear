module Entity
  def self.identifier_files(field)
    entity_type = Entity.formats[field]
    return [] unless entity_type and entity_type.include? Entity::Identified 
    entity_type.identifier_files
  end

  module Identified
    NAMESPACE_TAG = 'NAMESPACE'

    def self.included(base)
      base.extension_attr :format
      base.extension_attr :namespace

      class << base
        attr_accessor :identifier_files, :formats, :default_format, :name_format, :description_format
      end

      base.property :to => :both do |target_format|

        target_format = case target_format
                        when :name
                          identity_type.name_format 
                        when :default
                          identity_type.default_format 
                        else
                          target_format
                        end

        return self if target_format == format

        if Array === self
          self.annotate(identifier_index(target_format, self.format).values_at(*self))
        else
          self.annotate(identifier_index(target_format, self.format)[self])
        end.tap{|o| o.format = target_format unless o.nil? }
      end

      base.property :name => :both do
        to(:name)
      end

      base.property :default => :both do
        to(:default)
      end
    end

    def identifier_files 
      files = identity_type.identifier_files.dup
      return [] if files.nil?
      files.collect!{|f| f.annotate f.gsub(/\b#{NAMESPACE_TAG}\b/, namespace.to_s) } if extension_attrs.include? :namespace and self.namespace
      if files.select{|f| f =~ /\b#{NAMESPACE_TAG}\b/ }.any?
        Log.warn "Rejecting some identifier files for lack of 'namespace': " << files.select{|f| f =~ /\b#{NAMESPACE_TAG}\b/ } * ", "
      end
      files.reject!{|f| f =~ /\b#{NAMESPACE_TAG}\b/ } 
      files
    end

    def identity_type
      self.extension_types.select{|m| m.include? Entity::Identified }.last
    end

    def identifier_index(format = nil, source = nil)
      Persist.memory("Entity index #{identity_type}: #{format} (from #{source || "All"})", :persist => true, :format => format, :source => source) do
        source ||= self.respond_to?(:format)? self.format : nil

        begin
          index = TSV.translation_index(identifier_files, source, format, :persist => true)
          raise "No index from #{ Misc.fingerprint source } to #{ Misc.fingerprint format }: #{Misc.fingerprint identifier_files}" if index.nil?
          index.unnamed = true
          index
        rescue
          raise $! if source.nil?
          source = nil
          retry
        end
      end
    end
  end

  def add_identifiers(file, default = nil, name = nil, description = nil)
    if TSV === file
      all_fields = file.all_fields
    else
      if file =~ /#{Identified::NAMESPACE_TAG}/
        all_fields = file.sub(/#{Identified::NAMESPACE_TAG}/,'**').glob.collect do |f|
          TSV.parse_header(f)["all_fields"]
        end.flatten.compact.uniq
      else
        all_fields = TSV.parse_header(file)["all_fields"]
      end
    end

    self.send(:include, Entity::Identified) unless Entity::Identified === self

    self.format = all_fields
    @formats ||= []
    @formats.concat all_fields
    @formats.uniq!

    @default_format = default if default
    @name_format = name if name
    @description_format = description if description

    @identifier_files ||= []
    @identifier_files << file
    @identifier_files.uniq!
  end


end
