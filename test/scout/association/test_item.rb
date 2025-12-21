require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
require 'scout/association'
class TestAssociationItem < Test::Unit::TestCase
  def test_incidence
    pairs = [[:A, :a], [:B, :b]].collect{|p| "#{p.first.to_s}~#{p.last.to_s}"}
    assert TSV === AssociationItem.incidence(pairs)
    assert_equal 2, AssociationItem.incidence(pairs).length
    assert_equal 2, AssociationItem.incidence(pairs).fields.length

    associations = AssociationItem.setup(pairs)
    associations.extend AnnotatedArray

    assert_equal 2, associations.incidence.fields.length
  end

  def test_brothers
    incidence = TSV.incidence(datadir_test.person.brothers, undirected: true)
    assert incidence["Clei"]["Guille"]
    assert incidence["Guille"]["Clei"]
    refute incidence["Clei"]["Isa"]
  end
end

