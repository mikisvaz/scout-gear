module Workflow
  def persist(name, type = :serializer, options = {}, &block)
    options = IndiferentHash.add_defaults options, dir: Scout.var.workflows[self.name].persist
    Persist.persist(name, type, options, &block)
  end
end
