require_relative 'log/color'
require_relative 'log/fingerprint'
require_relative 'log/progress'
require_relative 'log/trap'

require 'io/console'

module Log
  class << self
    attr_accessor :severity
    attr_writer :tty_size, :logfile
  end

  SEVERITY_NAMES ||= begin
                       names = %w(DEBUG LOW MEDIUM HIGH INFO WARN ERROR NONE ) 
                       names.each_with_index do |name,i|
                         eval "#{ name } = #{ i }" 
                       end
                       names
                     end
  def self.default_severity
    @@default_severity ||= begin
                             file = File.join(ENV["HOME"], '.scout/etc/log_severity')
                             if File.exist? file
                               File.open(file) do |f|
                                 SEVERITY_NAMES.index f.read.strip
                               end
                             else
                               INFO
                             end
                           end
    @@default_severity
  end

  case ENV['SCOUT_LOG'] 
  when 'DEBUG' 
    self.severity = DEBUG
  when 'LOW' 
    self.severity = LOW
  when 'MEDIUM' 
    self.severity = MEDIUM
  when 'HIGH' 
    self.severity = HIGH
  when nil
    self.severity = default_severity
  else
    self.severity = default_severity
  end



  def self.tty_size
    @tty_size = begin
                  IO.console.winsize.last
                rescue
                  begin
                    `tput li`
                  rescue
                    80
                  end
                end
  end


  def self.last_caller(stack)
    line = nil
    pos ||= 0
    while line.nil? or line =~ /scout\/log\.rb/ and stack.any? 
      line = stack.shift 
    end
    line ||= caller.first
    line.gsub('`', "'")
  end

  def self.get_level(level)
    case level
    when Numeric
      level.to_i
    when String
      begin
        Log.const_get(level.upcase)
      rescue
        Log.exception $!
      end
    when Symbol
      get_level(level.to_s)
    end || 0
  end

  def self.with_severity(level)
    orig = Log.severity
    begin
      Log.severity = level
      yield
    ensure
      Log.severity = orig
    end
  end

  def self.logfile(file=nil)
    if file.nil?
      @logfile ||= nil
    else
      case file
      when String
        @logfile = File.open(file, :mode => 'a')
        @logfile.sync = true
      when IO, File
        @logfile = file
      else
        raise "Unkown logfile format: #{file.inspect}"
      end
    end
  end

  def self.up_lines(num = 1)
    nocolor ? "" : "\033[#{num+1}F\033[2K"
  end

  def self.down_lines(num = 1)
    nocolor ? "" : "\033[#{num+1}E"
  end

  def self.return_line
    nocolor ? "" : "\033[1A"
  end

  def self.clear_line(out = STDOUT)
    out.puts Log.return_line << " " * (Log.tty_size || 80) << Log.return_line unless nocolor
  end

  LAST = "log"
  def self.logn(message = nil, severity = MEDIUM, &block)
    return if severity < self.severity 
    message ||= block.call if block_given?
    return if message.nil?

    time = Time.now.strftime("%m/%d/%y-%H:%M:%S.%L")

    sev_str = severity.to_s

    prefix = time << color(severity) << "["  << sev_str << "]" << color(0)
    message = "" << highlight << message << color(0) if severity >= INFO
    str = prefix << " " << message.to_s

    if logfile.nil?
      STDERR.write str
    else
      logfile.write str 
    end
    Log::LAST.replace "log"
    nil
  end

  def self.log(message = nil, severity = MEDIUM, &block)
    return if severity < self.severity 
    message ||= block.call if block_given?
    return if message.nil?
    message = message + "\n" unless message[-1] == "\n"
    self.logn message, severity, &block
  end

  def self.log_obj_inspect(obj, level, file = $stdout)
    stack = caller

    line = Log.last_caller stack

    level = Log.get_level level
    name = Log::SEVERITY_NAMES[level] + ": "
    Log.log Log.color(level, name, true) << line, level
    Log.log "", level
    Log.log Log.color(level, "=> ", true) << obj.inspect, level
    Log.log "", level
  end

  def self.log_obj_fingerprint(obj, level, file = $stdout)
    stack = caller

    line = Log.last_caller stack

    level = Log.get_level level
    name = Log::SEVERITY_NAMES[level] + ": "
    Log.log Log.color(level, name, true) << line, level
    Log.log "", level
    Log.log Log.color(level, "=> ", true) << Log.fingerprint(obj), level
    Log.log "", level
  end

  def self.debug(message = nil, &block)
    log(message, DEBUG, &block)
  end

  def self.low(message = nil, &block)
    log(message, LOW, &block)
  end

  def self.medium(message = nil, &block)
    log(message, MEDIUM, &block)
  end

  def self.high(message = nil, &block)
    log(message, HIGH, &block)
  end

  def self.info(message = nil, &block)
    log(message, INFO, &block)
  end

  def self.warn(message = nil, &block)
    log(message, WARN, &block)
  end

  def self.error(message = nil, &block)
    log(message, ERROR, &block)
  end

  def self.exception(e)
    stack = caller
    backtrace = e.backtrace || []
    if ENV["SCOUT_ORIGINAL_STACK"] == 'true'
      error([e.class.to_s, e.message].compact * ": " )
      error("BACKTRACE [#{Process.pid}]: " << Log.last_caller(stack) << "\n" + color_stack(backtrace)*"\n")
    else
      error("BACKTRACE [#{Process.pid}]: " << Log.last_caller(stack) << "\n" + color_stack(backtrace.reverse)*"\n")
      error([e.class.to_s, e.message].compact * ": " )
    end
  end

  def self.deprecated(m)
    stack = caller
    warn("DEPRECATED: " << Log.last_caller(stack))
    warn("* " << (m || "").to_s)
  end

  def self.color_stack(stack)
    stack.collect do |line|
      line = line.sub('`',"'")
      color = :green if line =~ /workflow/
      color = :blue if line =~ /scout-/
      if color
        Log.color color, line
      else
        line
      end
    end unless stack.nil?
  end

  def self.tsv(tsv, example = false)
    STDERR.puts Log.color :magenta, "TSV log: " << Log.last_caller(caller).gsub('`',"'")
    STDERR.puts Log.color(:blue, "=> "<< Log.fingerprint(tsv), true) 
    STDERR.puts Log.color(:cyan, "=> " << tsv.summary)
    if example && ! tsv.empty?
      key = case example
            when TrueClass, :first, "first"
              tsv.keys.first
            when :random, "random"
              tsv.keys.shuffle.first
            else
              example
            end

      values = tsv[key]
      values = [values] if tsv.type == :flat || tsv.type == :single
      if values.nil?
        STDERR.puts Log.color(:blue, "Key (#{tsv.key_field}) not present: ") + key
      else
        STDERR.puts Log.color(:blue, "Key (#{tsv.key_field}): ") + key
        tsv.fields.zip(values).each do |field,value|
          STDERR.puts Log.color(:magenta, field + ": ") + (Array === value ? value * ", " : value.to_s)
        end
      end
    end
  end

  def self.stack(stack)
    if ENV["SCOUT_ORIGINAL_STACK"] == 'true'
      STDERR.puts Log.color :magenta, "Stack trace [#{Process.pid}]: " << Log.last_caller(caller)
      color_stack(stack).each do |line|
        STDERR.puts line
      end
    else
      STDERR.puts Log.color :magenta, "Stack trace [#{Process.pid}]: " << Log.last_caller(caller)
      color_stack(stack.reverse).each do |line|
        STDERR.puts line
      end
    end
  end

  def self.count_stack
    if ! $count_stacks
      Log.debug "Counting stacks at: " << caller.first
      return 
    end
    $stack_counts ||= {}
    head = $count_stacks_head
    stack = caller[1..head+1]
    stack.reverse.each do |line,i|
      $stack_counts[line] ||= 0
      $stack_counts[line] += 1
    end
  end

  def self.with_stack_counts(head = 10, total = 100)
    $count_stacks_head = head
    $count_stacks = true
    $stack_counts = {}
    res = yield
    $count_stacks = false
    Log.debug "STACK_COUNTS:\n" + $stack_counts.sort_by{|line,c| c}.reverse.collect{|line,c| [c, line] * " - "}[0..total] * "\n"
    $stack_counts = {}
    res
  end
end

def ppp(message)
  stack = caller
  puts "#{Log.color :cyan, "PRINT:"} " << stack.first
  puts ""
  if message.length > 200 or message.include? "\n"
    puts Log.color(:cyan, "=>|") << "\n" << message.to_s
  else
    puts Log.color(:cyan, "=> ") << message.to_s
  end
  puts ""
end

def fff(object)
  stack = caller
  Log.debug{"#{Log.color :cyan, "FINGERPRINT:"} " << stack.first}
  Log.debug{""}
  Log.debug{require 'scout/util/misc'; "=> " << Log.fingerprint(object) }
  Log.debug{""}
end

def ddd(obj, file = $stdout)
  Log.log_obj_inspect(obj, :debug, file)
end

def lll(obj, file = $stdout)
  Log.log_obj_inspect(obj, :low, file)
end

def mmm(obj, file = $stdout)
  Log.log_obj_inspect(obj, :medium, file)
end

def iii(obj=nil, file = $stdout)
  Log.log_obj_inspect(obj, :info, file)
end

def wwww(obj=nil, file = $stdout)
  Log.log_obj_inspect(obj, :warn, file)
end

def eee(obj=nil, file = $stdout)
  Log.log_obj_inspect(obj, :error, file)
end

def ddf(obj=nil, file = $stdout)
  Log.log_obj_fingerprint(obj, :debug, file)
end

def llf(obj=nil, file = $stdout)
  Log.log_obj_fingerprint(obj, :low, file)
end

def mmf(obj=nil, file = $stdout)
  Log.log_obj_fingerprint(obj, :medium, file)
end

def iif(obj=nil, file = $stdout)
  Log.log_obj_fingerprint(obj, :info, file)
end

def wwwf(obj=nil, file = $stdout)
  Log.log_obj_fingerprint(obj, :warn, file)
end

def eef(obj=nil, file = $stdout)
  Log.log_obj_fingerprint(obj, :error, file)
end

def sss(level, &block)
  if block_given?
    Log.with_severity level, &block
  else
    Log.severity = level
  end
end

$scout_debug_log = false
def ccc(obj=nil, file = $stdout)
  if block_given?
    old_scout_debug_log = $scout_debug_log
    $scout_debug_log = 'true'
    begin
      yield
    ensure
      $scout_debug_log = old_scout_debug_log
    end
  else
    Log.log_obj_inspect(obj, :info, file) if $scout_debug_log
  end
end


