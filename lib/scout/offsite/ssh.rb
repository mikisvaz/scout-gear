require 'net/ssh'
require_relative 'exceptions'

class SSHLine
  class << self
    attr_accessor :default_server
    def default_server
      @@default_server ||= begin
                             ENV["SCOUT_OFFSITE"] || ENV["SCOUT_SERVER"] || 'localhost'
                           end
    end
  end

  def initialize(host = :default, user = nil)
    host = SSHLine.default_server if host.nil? || host == :default
    @host = host
    @user = user

    @ssh = Net::SSH.start(@host, @user)

    @ch = @ssh.open_channel do |ch|
      ch.exec 'bash -l'
    end

    @ch.send_data("[[ -f ~/.scout/environment ]] && source ~/.scout/environment\n")
    @ch.send_data("[[ -f ~/.rbbt/environment ]] && source ~/.rbbt/environment\n")

    @ch.on_data do |_,data|
      if m = data.match(/DONECMD: (\d+)\n/)
        @exit_status = m[1].to_i
        @output << data.sub(m[0],'')
        serve_output 
      else
        @output << data
      end
    end

    @ch.on_extended_data do |_,c,err|
      STDERR.write err 
    end
  end


  def self.reach?(server = SSHLine.default_server)
    Persist.memory(server, :key => "Reach server") do
      begin
        CMD.cmd("ssh #{server} bash -l -c \"scout\"") 
        true
      rescue Exception
        false
      end
    end
  end

  def send_cmd(command)
    @output = ""
    @complete_output = false
    @ch.send_data(command+"\necho DONECMD: $?\n")
  end

  def serve_output
    @complete_output = true
  end

  def run(command)
    send_cmd(command)
    @ssh.loop{ ! @complete_output}
    if @exit_status.to_i == 0
      return @output
    else
      raise SSHProcessFailed.new @host, command
    end
  end

  def ruby(script)
    @output = ""
    @complete_output = false
    cmd = "ruby -e \"#{script.gsub('"','\\"')}\"\n"
    Log.debug "Running ruby on #{@host}:\n#{ script }"
    @ch.send_data(cmd)
    @ch.send_data("echo DONECMD: $?\n")
    @ssh.loop{ !@complete_output }
    if @exit_status.to_i == 0
      return @output
    else
      raise SSHProcessFailed.new @host, "Ruby script:\n#{script}"
    end
  end

  def scout(script)
    scout_script =<<-EOF
require 'scout'
SSHLine.run_local do
#{script.strip}
end
    EOF

    m = ruby(scout_script)
    Marshal.load m
  end

  def workflow(workflow, script)
    preamble =<<-EOF
wf = Workflow.require_workflow('#{workflow}')
    EOF

    scout(preamble + "\n" + script)
  end

  class Mock < SSHLine
    def initialize
    end

    def run(command)
      CMD.cmd(command)
    end

    def ruby(script)
      cmd = "ruby -e \"#{script.gsub('"','\\"')}\"\n"
      CMD.cmd(cmd)
    end
  end

  @connections = {}
  def self.open(host, user = nil)
    @connections[[host, user]] ||=
      begin
        if host == 'localhost'
          SSHLine::Mock.new
        else
          SSHLine.new host, user
        end
      end
  end

  def self.run(server, cmd, options = nil)
    cmd = cmd * " " if Array === cmd
    cmd += " " + CMD.process_cmd_options(options) if options
    open(server).run(cmd)
  end

  def self.ruby(server, script)
    open(server).ruby(script)
  end

  def self.scout(server, script)
    open(server).scout(script)
  end

  def self.workflow(server, workflow, script)
    open(server).workflow(workflow, script)
  end

  def self.command(server, command, argv = [], options = nil)
    command = "scout #{command}" unless command && command.include?('scout')
    argv_str = (argv - ["--"]).collect{|v| '"' + v.to_s + '"' } * " "
    command = "#{command} #{argv_str}"
    Log.debug "Offsite #{server} running: #{command}"
    run(server, command, options)
  end

  def self.mkdir(server, path)
    self.run server, "mkdir -p '#{path}'"
  end

  def self.run_local(&block)
    res = begin
            old_stdout = STDOUT.dup; STDOUT.reopen(STDERR)
            block.call
          ensure
            STDOUT.reopen(old_stdout)
          end
    puts Marshal.dump(res)
  end
end
