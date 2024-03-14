module Association
  def self.version_file(file, namespace)
    old_file, file = file, file.sub(Entity::Identified::NAMESPACE_TAG, namespace) if namespace and String === file
    old_file.annotate file if Path === old_file
    file
  end
end
