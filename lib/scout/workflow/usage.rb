require 'scout/simple_opt'

module Task
  def usage(workflow = nil, deps = nil)
    str = StringIO.new

    if description
      title, paragraph = description.split("\n\n")
      if title.length < Misc::MAX_TTY_LINE_WIDTH
        title = self.name.to_s + " - " + title
        str.puts Log.color :yellow, title
        str.puts Log.color :yellow, "-" * title.length
        if paragraph
          str.puts "\n" << Misc.format_paragraph(paragraph) 
        end
      else
        title = self.name.to_s
        str.puts Log.color :yellow, title
        str.puts Log.color :yellow, "-" * title.length
        str.puts "\n" << Misc.format_paragraph(description) 
      end
    else
      title = self.name.to_s
      str.puts Log.color :yellow, title
      str.puts Log.color :yellow, "-" * title.length
    end


    selects = []

    if inputs && inputs.any?
      str.puts
      str.puts Log.color(:magenta, "Inputs")
      str.puts
      str.puts SOPT.input_array_doc(inputs)

      inputs.select{|name,type, _| type == :select }.each do |name,_,_,_,options|
        selects << [name, options[:select_options]] if options[:select_options]
      end
    end

    deps = workflow ? workflow.recursive_deps(self.name) : self.deps if deps.nil?
    if deps and deps.any?
      seen = inputs.collect{|name,_| name }
      dep_inputs = {}
      deps.each do |dep_workflow,task_name,options|
        next if task_name.nil?
        task = dep_workflow.tasks[task_name]

        next if task.inputs.nil?

        inputs = task.inputs.reject{|name, _| seen.include? name }
        inputs = task.inputs.reject{|name, _| options.include? name }
        next unless inputs.any?
        input_names = inputs.collect{|name,_| name }
        task.inputs.select{|name,_| input_names.include? name }.each do |name,_,_,_,options|
          selects << [name, options[:select_options]] if options && options[:select_options]
        end

        dep = workflow.nil? || dep_workflow.name != workflow.name ? ["#{dep_workflow.name}", task_name.to_s] *"#" : task_name.to_s
        dep_inputs[dep] = inputs
      end

      str.puts
      str.puts Log.color(:magenta, "Inputs from dependencies:") if dep_inputs.any?
      dep_inputs.each do |dep,inputs|
        str.puts
        str.puts Log.color :yellow, dep + ":"
        str.puts
        str.puts SOPT.input_array_doc(inputs)
      end
    end

    case
    when inputs && inputs.select{|name,type| type == :array }.any?
      str.puts
      str.puts Log.color(:green, Misc.format_paragraph("Lists are specified as arguments using ',' or '|'. When specified as files the '\\n'
      also works in addition to the others. You may use the '--array_separator' option
      the change this default. Whenever a file is specified it may also accept STDIN using
      the '-' character."))

    when inputs && inputs.select{|name,type| type == :file || type == :tsv }.any?
      str.puts
      str.puts Log.color(:green, Misc.format_paragraph("Whenever a file is specified it may also accept STDIN using the '-' character."))
    end

    str.puts
    str.puts Log.color(:magenta, "Returns: ") << Log.color(:blue, type.to_s) << "\n"

    if selects.any?
      str.puts
      str.puts Log.color(:magenta, "Input select options")
      selects.collect{|p| p}.uniq.each do |input,options|
        str.puts 
        str.puts Log.color(:blue, input.to_s + ": ") << Misc.format_paragraph(options.collect{|o| Array === o ? o.first.to_s : o.to_s} * ", ") << "\n"
      end
    end
    str.rewind
    str.read
  end

  def SOPT_str
    sopt_options = []
    self.recursive_inputs.each do |name,type,desc,default,options|
      shortcut = (options && options[:shortcut]) || name.to_s.slice(0,1)
      boolean = type == :boolean

      sopt_options << "-#{shortcut}--#{name}#{boolean ? "" : "*"}"
    end

    sopt_options * ":"
  end

  def get_SOPT
    sopt_option_string = self.SOPT_str
    job_options = SOPT.get sopt_option_string

    recursive_inputs.uniq.each do |name,type|
      next unless type.to_s.include?('array')
      if job_options.include?(name) && (! Open.exist?(job_options[name]) || type.to_s.include?('file') || type.to_s.include?('path'))
        job_options[name] = job_options[name].split(",")
      end
    end
    job_options
  end
end

module Workflow

  def dep_tree(task_name, seen = nil, seen_options = nil)
    @dep_tree ||= {}
    key = [self, task_name]

    return @dep_tree[key] if @dep_tree.include?(key)
    save = seen.nil?
    seen = Set.new if seen.nil?
    seen_options = {} if seen_options.nil?

    dep_tree = {}
    task = self.tasks[task_name]
    raise TaskNotFound, "Task #{task_name} in #{self.to_s}" if task.nil?
    task.deps.each do |workflow, task, options|
      next if seen.include? dep
      seen << [workflow, task, options.merge(seen_options)]
      next if task.nil?

      key = [workflow, task]

      dep_tree[key] = workflow.dep_tree(task, seen, options.merge(seen_options))
    end if task.deps

    @dep_tree[key] = dep_tree if save

    dep_tree
  end

  def recursive_deps(task_name)
    dependencies = []
    dep_tree(task_name, dependencies)
    dependencies
  end

  def _prov_tasks(tree)
    tasks = [] 
    heap = tree.values
    while heap.any?
      t = heap.pop
      t.each do |k,v|
        tasks << k
        heap << v
      end
    end
    tasks
  end

  def prov_string(tree)
    description = ""

    last = nil
    seen = Set.new

    tasks = _prov_tasks(tree)
    tasks.each do |workflow,task_name|

      next if seen.include?([workflow,task_name])

      child = last && last.include?([workflow, task_name])
      first = last.nil?
      last = _prov_tasks(workflow.dep_tree(task_name))

      break if child

      if child
        description << "->" << task_name.to_s
      elsif first
        description << "" << task_name.to_s
      else
        description << ";" << task_name.to_s
      end
      
      seen << [workflow, task_name]
    end
    description
  end

  def prov_tree(tree, offset = 0, seen = [])

    return "" if tree.empty?

    lines = []

    offset_str = " " * offset

    lines << offset_str 

    tree.each do |p,dtree| 
      next if seen.include?(p)
      seen.push(p)
      workflow, task = p
      lines << offset_str + [workflow.to_s, task.to_s] * "#" + "\n" + workflow.prov_tree(dtree, offset + 1, seen)
    end

    lines * "\n"
  end

  def usage(task = nil, abridge = false)

    str = StringIO.new

    if self.documentation[:title] and not self.documentation[:title].empty?
      title = self.name + " - " + self.documentation[:title]
      str.puts Log.color :magenta, title
      str.puts Log.color :magenta, "=" * title.length
    else
      str.puts Log.color :magenta, self.name 
      str.puts Log.color :magenta, "=" * self.name.length
    end

    str.puts

    if tasks.nil?
      str.puts Log.color(:title, "No tasks")
    elsif task.nil?

      if self.documentation[:description] and not self.documentation[:description].empty?
        str.puts Misc.format_paragraph self.documentation[:description] 
        str.puts
      end

      str.puts Log.color :magenta, "## TASKS"
      if self.documentation[:task_description] and not self.documentation[:task_description].empty?
        str.puts
        str.puts Misc.format_paragraph self.documentation[:task_description] 
      end
      str.puts

      final = Set.new
      not_final = Set.new
      tasks.each do |name,task|
        tree = dep_tree(name)
        not_final += tree.keys
        final << name unless not_final.include?(name)
      end

      not_final.each do |p|
        final -= [p.last]
      end

      tasks.each do |name,task|
        description = task.description || ""
        description = description.split("\n\n").first

        next if abridge && ! final.include?(name)
        str.puts Misc.format_definition_list_item(name.to_s, description, nil, nil, :yellow)

        prov_string = prov_string(dep_tree(name))
        str.puts Misc.format_paragraph Log.color(:blue, "->" + prov_string) if prov_string && ! prov_string.empty?
      end 

    else

      if Task === task
        task_name = task.name
      else
        task_name = task
        task = self.tasks[task_name]
      end

      str.puts task.usage(self, self.recursive_deps(task_name))

      dep_tree = {[self, task_name] => dep_tree(task_name)}
      prov_tree = prov_tree(dep_tree)
      if prov_tree && ! prov_tree.empty? && prov_tree.split("\n").length > 2

        str.puts
        str.puts Log.color :magenta, "## DEPENDENCY GRAPH (abridged)"
        str.puts
        prov_tree.split("\n").each do |line|
          next if line.strip.empty?
          if m = line.match(/^( *)(\w+?)#(\w*)/i)
              offset, workflow, task_name =  m.values_at 1, 2, 3
              str.puts [offset, Log.color(:magenta, workflow), "#", Log.color(:yellow, task_name)] * ""
          else
            str.puts Log.color :blue, line 
          end
        end
        str.puts
      end
    end

    str.rewind
    str.read
  end

  def SOPT_str(task)
    sopt_options = []
    self.tasks[task].recursive_inputs.each do |name,type,desc,default,options|
      shortcut = options[:shortcut] || name.to_s.slice(0,1)
      boolean = type == :boolean

      sopt_options << "-#{short}--#{name}#{boolean ? "" : "*"}"
    end

    sopt_options * ":"
  end

  def get_SOPT(task)
    sopt_option_string = self.SOPT_str(task)
    SOPT.get sopt_option_string
  end

  def self.get_SOPT(workflow, task)
    workflow = Workflow.require_workflow workflow if String === workflow
    task = workflow.tasks[task.to_sym] if String === task || Symbol === task
    workflow.get_SOPT(task)
  end
end
