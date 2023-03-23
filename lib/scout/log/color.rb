require_relative 'color_class'
require_relative '../indiferent_hash'

require 'term/ansicolor'

module Colorize
  def self.colors=(colors)
    @colors = colors
  end

  def self.colors
    @colors ||= IndiferentHash.setup({green: "#00cd00" , red: "#cd0000" , yellow: "#ffd700" })
  end

  def self.diverging_colors=(colors)
    @diverging_colors = colors
  end

  def self.diverging_colors
    @diverging_colors ||=<<~EOF.split("\n")
      #a6cee3
      #1f78b4
      #b2df8a
      #33a02c
      #fb9a99
      #e31a1c
      #fdbf6f
      #ff7f00
      #cab2d6
      #6a3d9a
      #ffff99
      #b15928
    EOF
  end


  def self.from_name(color)
    return color if color =~ /^#?[0-9A-F]+$/i
    return colors[color.to_s] if colors.include?(color.to_s)

    case color.to_s
    when "white"
      '#000'
    when "black"
      '#fff'
    when 'green'
      colors["green3"] 
    when 'red'
      colors["red3"] 
    when 'yellow'
      colors["gold1"] 
    when 'blue'
      colors["RoyalBlue"] 
    else
      colors[color.to_s] || color
    end
  end

  def self.continuous(array, start = "#40324F", eend = "#EABD5D", percent = false) 
    start_color = Color.new from_name(start)
    end_color = Color.new from_name(eend)

    if percent
      array = array.collect{|v| n = v.to_f; n = n > 100 ? 100 : n; n < 0.001 ? 0.001 : n}
    else
      array = array.collect{|v| n = v.to_f; } 
    end
    max = array.max
    min = array.min
    range = max - min
    array.collect do |v|
      ratio = (v.to_f-min) / range
      start_color.blend end_color, ratio
    end
  end

  def self.gradient(array, value, start = :green, eend = :red, percent = false)
    index = array.index value
    colors = continuous(array, start, eend, percent)
    colors[index]
  end

  def self.rank_gradient(array, value, start = :green, eend = :red, percent = false)
    index = array.index value
    sorted = array.sort
    array = array.collect{|e| sorted.index e}
    colors = continuous(array, start, eend, percent)
    colors[index]
  end


  def self.distinct(array)
    colors = diverging_colors.collect{|c| Color.new c }

    num = array.uniq.length
    times = num / 12

    all_colors = colors.dup
    factor = 0.3 / times
    times.times do
      all_colors.concat  colors.collect{|n| n.darken(factor) }
    end

    value_color = Hash[*array.uniq.zip(all_colors).flatten]

    value_color.values_at *array
  end

  def self.tsv(tsv, options = {})
    values = tsv.values.flatten
    if Numeric === values.first or (values.first.to_f != 0 and values[0] != "0" and values[0] != "0.0")
      value_colors = IndiferentHash.process_to_hash(values){continuous(values)}
    else
      value_colors = IndiferentHash.process_to_hash(values){distinct(values)}
    end

    if tsv.type == :single
      Hash[*tsv.keys.zip(value_colors.values_at(*values)).flatten]
    else
      Hash[*tsv.keys.zip(values.collect{|vs| value_colors.values_at(*vs)}).flatten]
    end
  end
end

module Log
  extend Term::ANSIColor

  class << self
    attr_accessor :nocolor
  end

  self.nocolor = ENV["RBBT_NOCOLOR"] == 'true'

  WHITE, DARK, GREEN, YELLOW, RED = Color::SOLARIZED.values_at :base0, :base00, :green, :yellow, :magenta

  SEVERITY_COLOR = [reset, cyan, green, magenta, blue, yellow, red] #.collect{|e| "\033[#{e}"}
  HIGHLIGHT = "\033[1m"

  def self.uncolor(str)
    "" << Term::ANSIColor.uncolor(str)
  end

  def self.reset_color
    reset
  end

  def self.color(severity, str = nil, reset = false)
    return str.dup || "" if nocolor 
    color = reset ? Term::ANSIColor.reset : ""
    color << SEVERITY_COLOR[severity] if Integer === severity
    color << Term::ANSIColor.send(severity) if Symbol === severity and Term::ANSIColor.respond_to? severity 
    if str.nil?
      color
    else
      color + str.to_s + self.color(0)
    end
  end

  def self.highlight(str = nil)
    if str.nil?
      return "" if nocolor
      HIGHLIGHT
    else
      return str if nocolor
      HIGHLIGHT + str + color(0)
    end
  end

end
