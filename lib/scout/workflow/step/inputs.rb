class Step
  def save_inputs(inputs_dir)
    self.task.save_inputs(inputs_dir, provided_inputs)
  end
end
