require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'

class TestClass < Test::Unit::TestCase

  def test_sort_by_empty
    content =<<-EOF
#ID ValueA ValueB Comment
row1 a B c
row2 A b C
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(File.open(filename), :type => :list, :sep => /\s/)
      assert_equal %w(row2 row1), tsv.sort_by("ValueA").collect{|k,v| k}
      assert_equal %w(row1 row2), tsv.sort_by("ValueB").collect{|k,v| k}
    end
  end

  def test_sort_by
    content =<<-EOF
#ID ValueA ValueB Comment
row1 a B c
row2 A b C
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(File.open(filename), :type => :list, :sep => /\s/)
      assert_equal %w(row2 row1), tsv.sort_by("ValueA"){|k,v| v }.collect{|k,v| k}
      assert_equal %w(row1 row2), tsv.sort_by("ValueB"){|k,v| v }.collect{|k,v| k}
    end
  end

  def test_sort
    content =<<-EOF
#ID ValueA ValueB Comment
row1 a B c
row2 A b C
    EOF

    TmpFile.with_file(content) do |filename|
      tsv = TSV.open(File.open(filename), :type => :list, :sep => /\s/)
      assert_equal %w(row2 row1), tsv.sort("ValueA"){|a,b| a[1] <=> b[1] }.collect{|k,v| k}
      assert_equal %w(row1 row2), tsv.sort("ValueB"){|a,b| a[1] <=> b[1] }.collect{|k,v| k}
    end
  end
end

