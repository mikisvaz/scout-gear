module Persist
  def self.annotation_repo_persist(repo, name, &block)

    if String === repo
      repo = repo.find if Path === repo
      repo = Persist.open_tokyocabinet(repo, false, :list, :BDB)
      repo_fields = ["literal", "annotation_types", "JSON"]
      TSV.setup(repo, :fields => repo_fields, :key_field => "Annotation ID")
      repo.save_annotation_hash
    else
      repo_fields = repo.fields
    end

    subkey = name + ":"

    keys = repo.read_and_close do
      repo.range subkey + 0.chr, true, subkey + 254.chr, true
    end

    case
    when (keys.length == 1 and keys.first == subkey + 'NIL')
      nil
    when (keys.length == 1 and keys.first == subkey + 'EMPTY')
      []
    when (keys.length == 1 && keys.first =~ /:SINGLE$/)
      key = keys.first
      values = repo.with_read do
        repo[key]
      end
      Annotation.load_tsv_values(key, values, *repo_fields)
    when (keys.any? and not keys.first =~ /ANNOTATED_DOUBLE_ARRAY/)
      repo.with_read do
        keys.sort_by{|k| k.split(":").last.to_i}.collect{|key|
          v = repo[key]
          Annotation.load_tsv_values(key, v, *repo_fields)
        }
      end
    when (keys.any? and keys.first =~ /ANNOTATED_DOUBLE_ARRAY/)
      repo.with_read do

        res = keys.sort_by{|k| k.split(":").last.to_i}.collect{|key|
          v = repo[key]
          Annotation.load_tsv_values(key, v, *repo_fields)
        }

        res.first.annotate res
        res.extend AnnotatedArray

        res
      end
    else
      annotations = yield

      repo.write_and_read do 
        case
        when annotations.nil?
          repo[subkey + "NIL"] = nil
        when annotations.empty?
          repo[subkey + "EMPTY"] = nil
        when (not Array === annotations or (AnnotatedArray === annotations and not Array === annotations.first))
          tsv_values = Annotation.obj_tsv_values(annotations, repo_fields) 
          repo[subkey + annotations.id << ":" << "SINGLE"] = tsv_values
        when (not Array === annotations or (AnnotatedArray === annotations and AnnotatedArray === annotations.first))
          annotations.each_with_index do |e,i|
            next if e.nil?
            tsv_values = Annotation.obj_tsv_values(e, repo_fields) 
            repo[subkey + "ANNOTATED_DOUBLE_ARRAY:" << i.to_s] = tsv_values
          end
        else
          annotations.each_with_index do |e,i|
            next if e.nil?
            tsv_values = Annotation.obj_tsv_values(e, repo_fields) 
            repo[subkey + i.to_s] = tsv_values
          end
        end
      end

      annotations
    end

  end
end
