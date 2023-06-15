require 'workflow-scout'
require 'rbbt-scout'

module Scout
  def self.version
    Open.read(File.join(__dir__, '../VERSION'))
  end
end
