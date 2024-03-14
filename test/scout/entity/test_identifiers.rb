require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
require 'scout/entity'

class TestEntityIdentifiers < Test::Unit::TestCase
  setup do
    @m = Module.new do
      extend Entity
    end

    @m.add_identifiers datafile_test(Entity::Identified::NAMESPACE_TAG + '/identifiers'), "Name", "Alias"
  end

  teardown do
    Entity.formats.clear
  end

  def test_alias
    miguel = @m.setup("Miguel", namespace: :person)
    assert_equal "Miki", miguel.to("Alias")
  end

  def test_name_from_ID
    assert_equal "Miki", @m.setup("001", :format => 'ID', namespace: :person).to("Alias")
    assert_equal "Miguel", @m.setup("001", :format => 'ID', namespace: :person).to("Name")
    assert_equal ["Miguel"], @m.setup(["001"], :format => 'ID', namespace: :person).to("Name")
  end


  def test_identifier_files
    assert @m.identifier_files.any?
  end

  def test_Entity_identifier_files
    assert Entity.identifier_files("Name").any?
  end
end
