require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
class TestFixWidthTable < Test::Unit::TestCase
  def load_data(data)
    tsv = TSV.open(data, type: :list, :sep=>":", :cast => proc{|e| e =~ /(\s*)(_*)/; ($1.length..($1.length + $2.length - 1))})
    tsv.add_field "Start" do |key, values|
      values["Range"].first
    end
    tsv.add_field "End" do |key, values|
      values["Range"].last
    end

    tsv = tsv.slice ["Start", "End"]

    tsv
  end

  def test_open_fwt
    data =<<-EOF
##012345678901234567890
#ID:Range
a:   ______
b: ______
c:    _______
d:  ____
e:    ______
f:             ___
g:         ____
    EOF
    TmpFile.with_file(data) do |datafile|
      tsv = load_data(datafile)
      TmpFile.with_file do |filename|
        f = Persist.open_fwt filename, 100, true
        f.add_range tsv
        f.read

        assert_equal %w(), f.overlaps(0).sort
        assert_equal %w(1:6), f.overlaps(1).sort
        assert_equal %w(1:6:b), f.overlaps(1, true).sort
      end
    end
  end
end

