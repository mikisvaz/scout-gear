require 'workflow-scout'

module Scout
  def self.version
    Open.read(File.join(__dir__, '../VERSION'))
  end
end
