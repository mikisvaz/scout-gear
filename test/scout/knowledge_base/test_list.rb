require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/knowledge_base'
class TestKnowledgeBaseQuery < Test::Unit::TestCase
  def test_entity_list
    TmpFile.with_dir do |dir|
      kb = KnowledgeBase.new dir
      kb.register :brothers, datafile_test(:person).brothers, undirected: true
      kb.register :parents, datafile_test(:person).parents

      list = kb.subset(:brothers, :all).target_entity

      kb.save_list("bro_and_sis", list)
      assert_equal list, kb.load_list("bro_and_sis")

      assert_include kb.lists["Person"], "bro_and_sis"
      kb.delete_list("bro_and_sis")

      refute kb.lists["simple"]
    end
  end

  def test_simple_list
    list = ["Miki", "Isa"]
    TmpFile.with_dir do |dir|
      kb = KnowledgeBase.new dir

      kb.save_list("bro_and_sis", list)

      assert_equal list, kb.load_list("bro_and_sis")

      assert_include kb.lists["simple"], "bro_and_sis"

      kb.delete_list("bro_and_sis")

      refute kb.lists["simple"].any?
    end
  end
end
