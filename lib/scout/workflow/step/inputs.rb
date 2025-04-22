class Step
  def save_inputs(inputs_dir)
    if clean_name != name
      #hash = name[clean_name.length..-1]
      #inputs_dir += hash
      Log.medium "Saving job inputs to: #{Log.fingerprint inputs_dir}"
      self.task.save_inputs(inputs_dir, provided_inputs)
    else
      Log.medium "Saving no input job: #{Log.fingerprint inputs_dir}"
      Open.touch(inputs_dir)
    end
  end

  def save_input_bundle(input_bundle)
    TmpFile.with_file do |dir|
      save_inputs(dir)
      Open.mkdir File.dirname(input_bundle) 
      Misc.tarize dir, input_bundle
    end
  end
end
