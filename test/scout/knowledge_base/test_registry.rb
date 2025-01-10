require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/knowledge_base'

class TestKnowlegeBase < Test::Unit::TestCase
  def test_registry
    TmpFile.with_dir do |dir|
      brothers = datafile_test(:person).brothers
      kb = KnowledgeBase.new dir
      kb.register :brothers, brothers
      assert_include kb.all_databases, :brothers
    end
  end
end
