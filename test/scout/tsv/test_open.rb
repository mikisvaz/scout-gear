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

  def test_into_stream
    num_lines = 100
    lines = num_lines.times.collect{|i| "line-#{i}" }

    r = TSV.traverse lines, :into => :stream do |l|
      l + "-" + Process.pid.to_s
    end

    assert_equal num_lines, r.read.split("\n").length
  end

  def test_into_stream_error
    num_lines = 100
    lines = num_lines.times.collect{|i| "line-#{i}" }

    assert_raise ScoutException do
      Log.with_severity 7 do
        i = 0
        r = TSV.traverse lines, :into => :stream, cpus: 3 do |l|
          raise ScoutException if i > 10
          i += 1
          l + "-" + Process.pid.to_s
        end

        r.read
      end
    end
  end

  def test_into_dumper_error
    num_lines = 100
    lines = num_lines.times.collect{|i| "line-#{i}" }

    assert_raise ScoutException do 
      i = 0
      Log.with_severity 7 do
        dumper = TSV::Dumper.new :key_field => "Key", :fields => ["Value"], :type => :single
        dumper.init
        dumper = TSV.traverse lines, :into => dumper, :cpus => 3 do |l|
          raise ScoutException if i > 10
          i += 1
          value = l + "-" + Process.pid.to_s

          [i.to_s, value]
        end
        ppp dumper.stream.read
      end
    end
  end

  def test_traverse_line
    text=<<-EOF
#: :sep=" "
#Row LabelA LabelB LabelC
row1 A B C
row1 a b c
row2 AA BB CC
row2 aa bb cc
    EOF

    TmpFile.with_file(text) do |file|
      lines = Open.traverse file, :type => :line, :into => [] do |line|
        line
      end
      assert_include lines, "row2 AA BB CC"
    end
  end

  def test_collapse_stream
    text=<<-EOF
#: :sep=" "
#Row LabelA LabelB LabelC
row1 A B C
row1 a b c
row2 AA BB CC
row2 aa bb cc
    EOF

    s = StringIO.new text
    collapsed = TSV.collapse_stream(s)
    tsv = TSV.open collapsed 
    assert_equal ["A", "a"], tsv["row1"][0]
    assert_equal ["BB", "bb"], tsv["row2"][1]
  end

  def test_cpus_error_dumper
    num_lines = 100
    lines = num_lines.times.collect{|i| "line-#{i}" }

    dumper =  TSV::Dumper.new :key_field => "Key", :fields => ["Field"], type: :single
    dumper.init
    assert_raise ScoutException do
      Log.with_severity 7 do
        i = 0
        TSV.traverse lines, :into => dumper, cpus: 3 do |l|
          raise ScoutException if i > 10
          i += 1
          [Process.pid.to_s, l + "-" + Process.pid.to_s]
        end

      end
      ppp dumper.stream.read
    end
  end

  def test_step_travese_cpus

    size = 1000
    step = Step.new tmpdir.step[__method__] do
      lines = size.times.collect{|i| "line-#{i}" }
      Open.traverse lines, :type => :array, :into => :stream, :cpus => 3 do |line|
        line.reverse
      end
    end
    step.type = :array

    assert_equal size, step.run.length
  end
end

