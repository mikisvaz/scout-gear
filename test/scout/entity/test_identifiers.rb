require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
require 'scout/entity'

class TestEntityIdentifiers < Test::Unit::TestCase
  module Person
    extend Entity
  end

  Person.add_identifiers datafile_test('identifiers'), "Name", "Alias"

  def test_alias
    miguel = Person.setup("Miguel")
    assert_equal "Miki", miguel.to("Alias")
  end

  def test_name_from_ID
    assert_equal "Miki", Person.setup("001", :format => 'ID').to("Alias")
    assert_equal "Miguel", Person.setup("001", :format => 'ID').to("Name")
    assert_equal ["Miguel"], Person.setup(["001"], :format => 'ID').to("Name")
  end


  def test_identifier_files
    assert Person.identifier_files.any?
  end

  def test_Entity_identifier_files
    assert Entity.identifier_files("Name").any?
  end
end
