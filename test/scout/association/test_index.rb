require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
require 'scout/association'
class TestAssociationIndex < Test::Unit::TestCase
  def test_parents_simple
    database = Association.database datadir_test.person.parents
    index = Association.index datadir_test.person.parents
    assert_include index, "Miki~Juan"
  end

  def test_parents
    index = Association.index datadir_test.person.parents, target: "Parent=>Name", source: "=>Name"
    assert_include index, "Miguel~Juan Luis"
  end

  def test_brothers
    index = Association.index datadir_test.person.brothers, undirected: true, persist: false
    assert_include index, "Clei~Guille"
    assert_include index, "Guille~Clei"
  end

  def test_brothers_match
    index = Association.index datadir_test.person.brothers, undirected: true
    assert_equal ["Clei~Guille"], index.match("Clei")
    assert_equal ["Guille~Clei"], index.match("Guille")
  end

  def test_parents_subset
    index = Association.index datadir_test.person.parents
    assert_include index.subset(["Miki", "Guille"], :all), "Miki~Juan"
    assert_include index.subset(["Miki", "Guille"], :all), "Guille~Gloria"
  end

  def test_parents_reverse
    index = Association.index datadir_test.person.parents
    assert_include index.reverse.source_field, "Parent"
    assert_include index.reverse.subset(["Juan"], :all), "Juan~Miki"
  end

  def test_parents_filter
    index = Association.index datadir_test.person.parents
    assert_include index.filter('Type of parent', 'mother'), "Miki~Mariluz"
    assert_include index.filter('Type of parent', 'mother'), "Clei~Gloria"
    refute index.filter('Type of parent', 'mother').include?("Miki~Juan")
  end

  def test_parents_flat
    tsv = datadir_test.person.parents.tsv type: :flat, fields: ["Parent"]
    index = Association.index tsv
    assert_include index, "Miki~Juan"
    assert_include index, "Isa~Mariluz"
  end

end

