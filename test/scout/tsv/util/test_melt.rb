require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'

class TestClass < Test::Unit::TestCase
  def test_melt
    txt =<<-EOF
#: :sep=,#:type=:list
#Size,System1,System2
10,20,30
20,40,60
    EOF
    
    target =<<-EOF
#: :sep=,#:type=:list
#ID,Size,Time,System
10:0,10,20,System1
10:1,10,30,System2
20:0,20,40,System1
20:1,20,60,System2
    EOF

    tsv = TSV.open(txt)
    assert_equal tsv.melt_columns("Time", "System"), TSV.open(target)
  end
end

