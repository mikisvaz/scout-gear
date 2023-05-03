Persist.save_drivers[:tsv] = proc do |file| file.to_s end
Persist.load_drivers[:tsv] = proc do |file| TSV.open file end
