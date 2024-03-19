require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
class TestAssociation < Test::Unit::TestCase

  def test_marriages_simple
    database = Association.database(datadir_test.person.marriages, :source => "Wife", :target => "Husband")
    assert_equal "001", database["002"]["Husband"]
    assert_equal "2021", database["002"]["Date"]
  end

  def test_marriages_open
    database = Association.database(datadir_test.person.marriages, :source => "Wife (ID)=>Alias", :target => "Husband (ID)=>Name")
    assert_equal "Miguel", database["Clei"]["Husband"]
    assert_equal "2021", database["Clei"]["Date"]
    assert_include database.key_field, "Alias"
  end

  def test_marriages_partial_field
    database = Association.database(datadir_test.person.marriages, :source => "Wife=>Alias", :target => "Husband=>Name")
    assert_equal "Miguel", database["Clei"]["Husband"]
    assert_equal "2021", database["Clei"]["Date"]
    assert_include database.key_field, "Alias"
    assert_include database.fields.first, "Name"
  end

  def test_marriages_open_from_tsv
    database = Association.database(datadir_test.person.marriages.tsv, :source => "Wife (ID)=>Alias", :target => "Husband (ID)=>Name")
    assert_equal "Miguel", database["Clei"]["Husband"]
    assert_equal "2021", database["Clei"]["Date"]
    assert_include database.key_field, "Alias"
  end
  
  def test_brothers_id
    database = Association.database(datadir_test.person.brothers, :source => "Older=~Older (Alias)=>Name", :target => "Younger=~Younger (Alias)=>ID")
    assert_equal '001', database["Isabel"]["Younger"]
  end

  def test_brothers_rename
    database = Association.database(datadir_test.person.brothers, :source => "Older=~Older (Alias)=>Name")
    assert_equal "Older (Name)", database.key_field
  end

  def test_parents_flat
    tsv = datadir_test.person.parents.tsv type: :flat, fields: ["Parent"]
    database = Association.database(tsv)
    assert_equal database["Miki"], %w(Juan Mariluz)
  end
end

