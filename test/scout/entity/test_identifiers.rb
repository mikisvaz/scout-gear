require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
require 'scout/entity'

class TestEntityIdentifiers < Test::Unit::TestCase
  module Person
    extend Entity
  end

  module PersonWithNoIds
    extend Entity
    include Entity::Identified
  end

  Person.add_identifiers datafile_test(Entity::Identified::NAMESPACE_TAG + '/identifiers'), "Name", "Alias"

  #teardown do
  #  Entity.formats.clear
  #end

  def test_alias
    miguel = Person.setup("Miguel", namespace: :person)
    assert_equal "Miki", miguel.to("Alias")
  end

  def test_alias_no_namespace
    miguel = Person.setup("Miguel")

    assert_raise do
      miguel.to("Name")
    end
  end

  def test_alias_no_ids
    miguel = PersonWithNoIds.setup("Miguel", namespace: :person)
    assert_raise do
      miguel.to("Name")
    end
  end


  def test_name_from_ID
    assert_equal "Miki", Person.setup("001", :format => 'ID', namespace: :person).to("Alias")
    assert_equal "Miguel", Person.setup("001", :format => 'ID', namespace: :person).to("Name")
    assert_equal ["Miguel"], Person.setup(["001"], :format => 'ID', namespace: :person).to("Name")
  end


  def test_identifier_files
    assert Person.identifier_files.any?
  end

  def test_Entity_identifier_files
    assert Entity.identifier_files("Name").any?
  end
end
