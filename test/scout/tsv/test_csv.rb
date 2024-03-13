require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')
require 'scout/tsv'

class TestTSVCSV < Test::Unit::TestCase
  def test_csv
    text =<<-EOF
Key,FieldA,FieldB
k1,a,b
k2,aa,bb
    EOF

    tsv = TSV.csv(text)
    assert_equal 'bb', tsv['k2']['FieldB']
  end

  def test_csv_key_field
    text =<<-EOF
Key,FieldA,FieldB
k1,a,b
k2,aa,bb
    EOF

    tsv = TSV.csv(text, :key_field => 'FieldA', :type => :list)
    assert_equal 'bb', tsv['aa']['FieldB']
  end

  def test_csv_double
    text =<<-EOF
Key,FieldA,FieldB
k1,a,b
k2,aa,bb
    EOF

    tsv = TSV.csv(text, :key_field => 'FieldA', :type => :double)
    assert_equal ['bb'], tsv['aa']['FieldB']
  end

  def test_csv_noheader
    text =<<-EOF
k1,a,b
k2,aa,bb
    EOF

    tsv = TSV.csv(text, :headers => false)
    assert_equal %w(k2 aa bb), tsv['row-1']
  end

end

