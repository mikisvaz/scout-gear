require 'scout/config'

class Step
  def config(key, *tokens)
    options = tokens.pop if Hash === tokens.last
    options ||= {}

    new_tokens = []
    if workflow
      workflow_name = workflow.name
      new_tokens << ("workflow:" + workflow_name)
      new_tokens << ("task:" + workflow_name << "#" << task_name.to_s)
    end
    new_tokens << ("task:" + task_name.to_s)
    new_tokens << (task_name.to_s)
    new_tokens << (workflow_name)
    new_tokens << ("task")

    Scout::Config.get(key, tokens + new_tokens, options)
  end
end
