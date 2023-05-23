module Misc
  def self.env_add(var, value, sep = ":", prepend = true)
    if ENV[var].nil?
      ENV[var] = value
    elsif ENV[var] =~ /(#{sep}|^)#{Regexp.quote value}(#{sep}|$)/
      return
    else
      if prepend
        ENV[var] = value + sep + ENV[var]
      else
        ENV[var] += sep + value
      end
    end
  end

  def self.with_env(var, value, &block)
    old_value = ENV[var]
    begin
      ENV[var] = value
      yield
    ensure
      ENV[var] = old_value
    end
  end
end
