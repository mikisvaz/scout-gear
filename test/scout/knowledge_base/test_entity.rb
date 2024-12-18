require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/knowledge_base'


class TestKnowledgeBaseQuery < Test::Unit::TestCase
  def test_types
    TmpFile.with_dir do |dir|
      kb = KnowledgeBase.new dir
      kb.register :brothers, datafile_test(:person).brothers, undirected: true
      kb.register :parents, datafile_test(:person).parents

      assert_include kb.all_databases, :brothers

      assert_equal Person, kb.target_type(:parents)
    end
  end

  def test_options
    TmpFile.with_dir do |dir|
      kb = KnowledgeBase.new dir
      kb.register :brothers, datafile_test(:person).brothers, undirected: true
      kb.entity_options = { "Person" => {language: "es"} }

      assert_include kb.entity_options_for("Person"), :language
    end
  end

  def test_identify
    TmpFile.with_dir do |dir|
      kb = KnowledgeBase.new dir
      kb.register :brothers, datafile_test(:person).brothers, undirected: true

      assert_equal "Miki", kb.identify(:brothers, "001")
    end
  end
end
