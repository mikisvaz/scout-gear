require_relative 'association'
require_relative 'association/item'
require_relative 'knowledge_base/registry'
require_relative 'knowledge_base/entity'
require_relative 'knowledge_base/query'
require_relative 'knowledge_base/traverse'
require_relative 'knowledge_base/list'
require_relative 'knowledge_base/description'
#require 'scout/knowledge_base/query'
#require 'scout/knowledge_base/syndicate'

class KnowledgeBase

  attr_accessor :dir, :namespace, :registry, :entity_options, :format, :identifier_files

  def initialize(dir, namespace = nil)
    @dir = Path.setup(dir.dup)

    @namespace = namespace

    @identifier_files = []

    @registry       ||= IndiferentHash.setup({})
    @entity_options ||= IndiferentHash.setup({})

    @format         ||= IndiferentHash.setup({})
    pairs          ||= IndiferentHash.setup({})
    @indices        ||= IndiferentHash.setup({})
  end

  def config_file(name)
    @dir.config[name.to_s]
  end

  def save_variable(name)
    file = config_file(name)
    variable = "@#{name}".to_sym
    Open.write(file, self.instance_variable_get(variable).to_yaml)
  end

  def load_variable(name)
    file = config_file(name)
    variable = "@#{name}".to_sym
    self.instance_variable_set(variable, YAML.load(Open.read(file))) if file.exists?
  end

  def save
    save_variable(:namespace)
    save_variable(:registry)
    save_variable(:entity_options)
    save_variable(:identifier_files)
  end

  def load
    load_variable(:namespace)
    load_variable(:registry)
    load_variable(:entity_options)
    load_variable(:identifier_files)
  end

  def self.load(dir)
    dir = Path.setup("var").knowledge_base[dir.to_s] if Symbol === dir
    kb = KnowledgeBase.new dir
    kb.load
    kb
  end

  def info(name)

    source = self.source(name)
    target = self.target(name)
    source_type = self.source_type(name)
    target_type = self.target_type(name)
    fields = self.fields(name)
    source_entity_options = self.entity_options_for source_type, name
    target_entity_options = self.entity_options_for target_type, name
    undirected = self.undirected(name) == 'undirected'

    info = {
      :source => source,
      :target => target,
      :source_type => source_type,
      :target_type => target_type,
      :source_entity_options => source_entity_options,
      :target_entity_options => target_entity_options,
      :fields => fields,
      :undirected => undirected,
    }

    info
  end
end
