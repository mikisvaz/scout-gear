require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestKnowlegeBase < Test::Unit::TestCase
  def test_no_namespace
    TmpFile.with_dir do |dir|
      kb = KnowledgeBase.new dir
      assert_nil kb.namespace
      kb.save

      kb = KnowledgeBase.load dir
      assert_nil kb.namespace
    end
  end

  def test_namespace
    TmpFile.with_dir do |dir|
      kb = KnowledgeBase.new dir, "Hsa"
      assert_equal "Hsa", kb.namespace
      kb.save

      kb = KnowledgeBase.load dir
      assert_equal "Hsa", kb.namespace
    end
  end
end

