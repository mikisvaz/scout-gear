require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
class TestOpenTraverse < Test::Unit::TestCase
  def test_array
    num_lines = 100
    lines = num_lines.times.collect{|i| "line-#{i}" }

    r = TSV.traverse lines, :into => [] do |l|
      l + "-" + Process.pid.to_s
    end

    assert_equal num_lines, r.length
  end

  def test_array_cpus
    num_lines = 1000
    lines = num_lines.times.collect{|i| "line-#{i}" }

    r = TSV.traverse lines, :into => [], :cpus => 2 do |l|
      l + "-" + Process.pid.to_s
    end

    assert_equal num_lines, r.length
    assert_equal 2, r.collect{|l| l.split("-").last}.uniq.length
  end

  def test_tsv_cpus
    num_lines = 10000
    lines = num_lines.times.collect{|i| "line-#{i}" }

    tsv  = TSV.setup({}, key_field: "Line", :fields => %w(Prefix Number), :type => :list)
    lines.each do |line|
      tsv[line] = ["LINE", line.split("-").last]
    end

    r = TSV.traverse tsv, :into => [], :cpus => 2, :bar => {desc: "Process", severity: 0} do |l,v|
      pre, num = v
      pre + "-" + num.to_s + "-" + Process.pid.to_s
    end

    assert_equal num_lines, r.length
    assert_equal 2, r.collect{|l| l.split("-").last}.uniq.length
    assert_equal "LINE", r.collect{|l| l.split("-").first}.first
  end
end

