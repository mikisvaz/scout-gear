require_relative 'misc/format'
module Misc
  def self.in_dir(dir)
    old_pwd = FileUtils.pwd
    begin
      FileUtils.mkdir_p dir unless File.exist?(dir)
      FileUtils.cd dir
      yield
    ensure
      FileUtils.cd old_pwd
    end
  end

end
