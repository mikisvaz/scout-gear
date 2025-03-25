require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestWorkflowEntity < Test::Unit::TestCase
  def get_EWF
    @m ||= Module.new do
      extend EntityWorkflow

      self.name = 'TestEWF'

      property :introduction do
        "Mi name is #{self}"
      end

      entity_task hi: :string do
        "Hi. #{entity.introduction}"
      end

      list_task group_hi: :string do
        "Here is the group: " + entity_list.hi * "; "
      end

      list_task bye: :array do
        entity_list.collect do |e|
          "Bye from #{e}"
        end
      end
    end
  end

  def test_property_job
    ewf = get_EWF

    e = ewf.setup("Miki")

    assert_equal "Mi name is Miki", e.introduction
    assert_equal "Hi. Mi name is Miki", e.hi
  end

  def test_list
    ewf = get_EWF
    
    l = ewf.setup(["Miki", "Clei"])

    assert_equal 2, l.hi.length

    assert_include l.group_hi, "group: "
  end

  def test_multiple
    ewf = get_EWF
    
    l = ewf.setup(["Miki", "Clei"])

    assert_equal 2, l.bye.length
  end
end

