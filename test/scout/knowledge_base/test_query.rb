require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/knowledge_base'


class TestKnowledgeBaseQuery < Test::Unit::TestCase
  def test_query
    TmpFile.with_dir do |dir|
      kb = KnowledgeBase.new dir
      kb.entity_options = {"Person" => {language: "es"}}

      kb.register :brothers, datafile_test(:person).brothers, undirected: true
      kb.register :parents, datafile_test(:person).parents, entity_options: {"Person" => {language: "en"}}

      assert_include kb.all_databases, :brothers

      matches = kb.subset(:parents, :all)
      assert_include matches, "Clei~Domingo"

      matches = kb.subset(:parents, target: :all, source: ["Miki"])
      assert_include matches, "Miki~Juan"


      assert_include kb.children(:parents, "Miki").target, "Juan"
      assert_include kb.children(:brothers, "Miki").target, "Isa"

      parents = matches.target_entity

      assert_include parents, "Juan"
      assert Person === parents.first
      assert_equal "en", parents.first.language


      matches = kb.subset(:brothers, target: :all, source: ["Miki"])
      assert_equal "es", matches.first.source_entity.language
    end
  end
end
