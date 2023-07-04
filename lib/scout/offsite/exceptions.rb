class SSHProcessFailed < StandardError
  attr_accessor :host, :cmd
  def initialize(host, cmd)
    @host = host
    @cmd = cmd
    message = "SSH server #{host} failed cmd '#{cmd}'" 
    super(message)
  end
end
