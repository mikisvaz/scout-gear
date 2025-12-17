require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/knowledge_base'
class TestKnowledgebaseDesc < Test::Unit::TestCase
  def test_brothers_registry
    TmpFile.with_dir do |dir|
      brothers = datafile_test(:person).brothers
      kb = KnowledgeBase.new dir
      kb.register :brothers, brothers, description: "Sibling relationships."
      assert_equal "Sibling relationships.", kb.description(:brothers)
    end
  end

  def test_brothers_README
    TmpFile.with_dir do |dir|
      brothers = datafile_test(:person).brothers
      kb = KnowledgeBase.new dir
      kb.register :brothers, brothers
      kb.dir['brothers.md'].write "Sibling relationships."
      assert_equal "Sibling relationships.", kb.description(:brothers)
    end
  end

  def test_broters_kb_README
    TmpFile.with_dir do |dir|
      brothers = datafile_test(:person).brothers
      kb = KnowledgeBase.new dir
      kb.register :brothers, brothers
      kb.dir['README.md'].write <<-EOF
Databases describing people and their relationships.

# Brothers

Sibling relationships.
      EOF
      assert_equal "Sibling relationships.", kb.description(:brothers)
    end
  end

  def test_brothers_kb_source_README
    TmpFile.with_dir do |dir|
      brothers = datafile_test(:person).brothers
      kb = KnowledgeBase.new dir
      kb.register :brothers, brothers
      assert_include kb.description(:brothers), "Sibling relationships."
    end
  end

  def test_full_description
    TmpFile.with_dir do |dir|
      brothers = datafile_test(:person).brothers
      kb = KnowledgeBase.new dir
      kb.register :brothers, brothers
      assert_include kb.markdown(:brothers), "Older"
    end
  end
end

