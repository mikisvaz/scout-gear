require 'scout/annotation'
class KnowledgeBase

  def list_file(id, entity_type = nil)
    id = Path.sanitize_filename(id)

    entity_type = entity_type.to_s.split(":").last

    raise "Ilegal list id: #{ id }" unless Misc.path_relative_to(dir, File.join(dir, id))

    if entity_type
      if entity_type.to_s == "simple"
        path = dir.lists[entity_type.to_s][id]
      else
        path = dir.lists[entity_type.to_s][id].find_with_extension("tsv")
      end
    else
      path = dir.lists.glob("*/#{id}").first
      path ||= dir.lists.glob("*/#{id}.tsv").first
      raise "List not found #{id}" if path.nil?
    end

    path.find
  end

  def save_list(id, list)
    if AnnotatedArray === list
      path = list_file(id, list.base_entity)
    else
      path = list_file(id, :simple)
    end

    Open.lock path do
      begin
        if AnnotatedArray === list
          path = path.set_extension('tsv')
          Open.write(path, Annotation.tsv(list, :all).to_s)
        else
          Open.write(path, list * "\n")
        end
      rescue
        FileUtils.rm(path) if File.exist?(path)
        raise $!
      end
    end
  end

  def load_list(id, entity_type = nil)
    if entity_type
      path = list_file(id, entity_type) 
      path = list_file(id) unless path.exists?
    else
      path = list_file(id)
    end

    raise "List not found: #{ id }" unless path and path.exists?

    begin
      if path.get_extension == 'tsv'
        list = Annotation.load_tsv path.tsv
        list.extend AnnotatedArray
        list
      else
        list = path.list
        if entity_type
          Entity.prepare_entity(list, entity_type)
        end
        list
      end
    rescue
      Log.exception $!
      nil
    end
  end

  def lists
    lists = {}
    dir.lists.glob("*").each do |list_dir|
      lists[list_dir.basename] = list_dir.glob("*").
        collect(&:unset_extension).
        collect(&:basename)
    end
    lists
  end

  def delete_list(id, entity_type = nil)
    path = list_file(id, entity_type)
    path = list_file(id) unless path.exists?

    "This list does not belong to #{ user }: #{[entity_type, id] * ": "}" unless File.exist? path

    Open.lock path do
      begin
        FileUtils.rm path if File.exist? path
      rescue
        raise $!
      end
    end
  end
end
