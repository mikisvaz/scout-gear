require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestEntity < Test::Unit::TestCase

  setup do
    Entity.entity_property_cache = tmpdir.property_cache
  end

  module EmptyEntity
    extend Entity
  end

  def test_person
    person = Person.setup("Miguel", 'es')
    assert_equal "Hola Miguel", person.salutation

    person.language = 'en'
    assert_equal "Hi Miguel", person.salutation
  end

  def test_empty
    refute EmptyEntity.setup("foo").nil?
  end
end
