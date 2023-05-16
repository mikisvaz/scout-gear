require_relative '../../named_array'
module Task
  def format_input(value, type, options = {})
    return value if IO === value || StringIO === value

    value = value.load if Step === value
    if String === value && ! [:path, :file, :folder].include?(type) 
      if Open.exists?(value) && ! Open.directory?(value)
        Persist.load(value, type) 
      else
        Persist.deserialize(value, type)
      end
    else
      if m = type.to_s.match(/(.*)_array/)
        if Array === value
          value.collect{|v| format_input(v, m[1].to_sym, options) }
        end
      else
        value
      end
    end
  end

  def assign_inputs(provided_inputs = {})
    if self.inputs.nil? || (self.inputs.empty? && Array === provided_inputs)
      case provided_inputs
      when Array
        return [provided_inputs, provided_inputs]
      else
        return [[], []]
      end
    end

    IndiferentHash.setup(provided_inputs) if Hash === provided_inputs

    input_array = []
    input_names = []
    non_default_inputs = []
    self.inputs.each_with_index do |p,i|
      name, type, desc, value, options = p
      input_names << name
      provided = Hash === provided_inputs ? provided_inputs[name] : provided_inputs[i]
      provided = format_input(provided, type, options || {})
      if ! provided.nil? && provided != value
        non_default_inputs << name.to_sym
        input_array << provided
      else
        input_array << value
      end
    end

    NamedArray.setup(input_array, input_names)

    [input_array, non_default_inputs]
  end

  def process_inputs(provided_inputs = {})
    input_array, non_default_inputs = assign_inputs provided_inputs
    digest = Misc.digest(input_array)
    [input_array, non_default_inputs, digest]
  end

  def save_file_input(orig_file, directory)
    basename = File.basename(orig_file)
    digest = Misc.digest(orig_file)
    if basename.include? '.'
      basename.sub!(/(.*)\.(.*)/, "\1-#{digest}.\2")
    else
      basename += "-#{digest}"
    end
    new_file = File.join(directory, 'saved_input_files', basename)
    relative_file = File.join('.', 'saved_input_files', basename) 
    Open.link orig_file, new_file
    relative_file
  end

  def save_inputs(directory, provided_inputs = {})
    input_array, non_default_inputs = assign_inputs(provided_inputs)
    self.inputs.each_with_index do |p,i|
      name, type, desc, value, options = p
      next unless non_default_inputs.include?(name)
      input_file = File.join(directory, name.to_s)

      if type == :file
        relative_file = save_file_input(input_array[i], directory)
        Persist.save(relative_file, input_file, type)
      elsif type == :file_array
        new_files = input_array[i].collect do |orig_file|
          save_file_input(orig_file, directory)
        end
        Persist.save(new_files, input_file, type)
      else
        Persist.save(input_array[i], input_file, type)
      end
    end
  end

  def load_inputs(directory)
    self.inputs.collect do |p|
      name, type, desc, value, options = p
      filename = File.join(directory, name.to_s) 
      if Open.exists?(filename) || filename = Dir.glob(File.join(filename + ".*")).first
        Persist.load(filename, type)
      else
        value
      end
    end
  end
end
