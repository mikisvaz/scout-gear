class Step
  def recursive_inputs
    dependencies.inject(@inputs.annotate(@inputs.dup)) do |acc,dep|
      acc.concat(dep.inputs) if dep.inputs
      acc
    end
  end

  def input_dependencies
    return [] unless inputs
    inputs.select do |d|
      Step === d
    end
  end

  def prepare_dependencies
    inverse_dep = {}
    dependencies.each{|dep| 
      next if dep.done?
      if dep.dependencies
        dep.dependencies.each do |d|
          inverse_dep[d] ||= []
          inverse_dep[d] << dep 
        end
      end
      input_dependencies.each do |d|
        inverse_dep[d] ||= []
        inverse_dep[d] << dep 
      end
    }
    inverse_dep.each do |dep,list|
      dep.tee_copies = list.length
    end
  end

  def run_dependencies
    dependencies.each{|dep| dep.run unless dep.running? || dep.done? }
  end

end
