require_relative '../../named_array'
module Task
  def self.format_input(value, type, options = {})
    return value if IO === value || StringIO === value || Step === value

    if String === value && ! [:path, :file, :folder, :binary].include?(type) && ! (options &&  (options[:noload] || options[:stream] || options[:nofile]))
      if Open.exists?(value) && ! Open.directory?(value)
        Persist.load(value, type) 
      else
        Persist.deserialize(value, type)
      end
    else
      if m = type.to_s.match(/(.*)_array/)
        if Array === value
          value.collect{|v| self.format_input(v, m[1].to_sym, options) }
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
      provided = Task.format_input(provided, type, options || {})
      if ! provided.nil? && provided != value
        non_default_inputs << name.to_sym
        input_array << provided
      elsif options && options[:jobname]
        input_array << provided_inputs[:jobname]
      else
        input_array << value
      end
    end

    NamedArray.setup(input_array, input_names)

    [input_array, non_default_inputs]
  end

  def process_inputs(provided_inputs = {})
    input_array, non_default_inputs = assign_inputs provided_inputs
    digest_str = Misc.digest_str(input_array)
    [input_array, non_default_inputs, digest_str]
  end

  def save_file_input(orig_file, directory)
    basename = File.basename(orig_file)
    digest = Misc.digest(orig_file)
    if basename.include? '.'
      basename.sub!(/(.*)\.(.*)/, '\1-' + digest + '.\2')
    else
      basename += "-#{digest}"
    end
    new_file = File.join(directory, 'saved_input_files', basename)
    relative_file = File.join('.', 'saved_input_files', basename) 
    Open.link orig_file, new_file
    relative_file
  end

  def save_inputs(directory, provided_inputs = {})
    #input_array, non_default_inputs = assign_inputs(provided_inputs)
    self.recursive_inputs.each_with_index do |p,i|
      name, type, desc, value, options = p
      next unless provided_inputs.include?(name)
      value = provided_inputs[name]
      input_file = File.join(directory, name.to_s)

      if type == :file
        relative_file = save_file_input(value, directory)
        Persist.save(relative_file, input_file, :file)
      elsif type == :file_array
        new_files = value.collect do |orig_file|
          save_file_input(orig_file, directory)
        end
        Persist.save(new_files, input_file, type)
      elsif Path.is_filename?(value) 
        relative_file = save_file_input(value, directory)
        Open.write(input_file + ".as_file", relative_file)
      elsif Open.is_stream?(value)
        Persist.save(input_file, value, type)
      elsif Open.has_stream?(value)
        Persist.save(input_file, value.stream, type)
      else
        Persist.save(value, input_file, type)
      end
    end
  end

  def load_inputs(directory)
    inputs = IndiferentHash.setup({})
    self.recursive_inputs.each do |p|
      name, type, desc, value, options = p
      filename = File.join(directory, name.to_s) 
      if Open.exists?(filename) || filename = Dir.glob(File.join(filename + ".*")).first
        if filename.end_with?('.as_file')
          value = Open.read(filename).strip
          value.sub!(/^\./, File.dirname(filename)) if value.start_with?("./")
          inputs[name] = value
        elsif (options &&  (options[:noload] || options[:stream] || options[:nofile]))
          inputs[name] = filename
        else
          inputs[name] = Persist.load(filename, type)
        end
      end
    end
    inputs
  end
end
