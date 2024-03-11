require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestEntity < Test::Unit::TestCase

  module Person
    extend Entity

    extension_attr :language

    property :salutation do
      case language
      when 'es'
        "Hola #{self}"
      else
        "Hi #{self}"
      end
    end
  end


  def test_person
  
    person = Person.setup("Miguel", 'es')
    assert_equal "Hola Miguel", person.salutation

    person.language = 'en'
    assert_equal "Hi Miguel", person.salutation
  end
end

