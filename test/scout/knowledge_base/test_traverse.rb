require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/knowledge_base'
class TestKnowledgeBaseTraverse < Test::Unit::TestCase
  def test_traverse_single
    TmpFile.with_dir do |dir|
      kb = KnowledgeBase.new dir
      kb.entity_options = {"TestKnowledgeBaseQuery::Person" => {test: "Default"}}

      kb.register :brothers, datafile_test(:person).brothers, undirected: true
      kb.register :parents, datafile_test(:person).parents, entity_options: {"TestKnowledgeBaseQuery::Person" => {test: "Parents"}}

      rules = []
      rules << "Miki brothers ?1"
      res =  kb.traverse rules
      assert_include res.first["?1"], "Isa"

      rules = []
      rules << "Miki parents ?1"
      entities, paths =  kb.traverse rules
      assert_include paths.first.first.info, "Type of parent"

      rules = []
      rules << "?1 parents Domingo"
      entities, paths =  kb.traverse rules
      assert_include entities["?1"], "Clei"
    end
  end

  def test_traverse_multiple
    TmpFile.with_dir do |dir|
      kb = KnowledgeBase.new dir

      kb.register :brothers, datafile_test(:person).brothers, undirected: true
      kb.register :parents, datafile_test(:person).parents
      kb.register :marriages, datafile_test(:person).marriages, source: "=>Alias", target: "=>Alias"

      rules = []
      rules << "Miki marriages ?1"
      rules << "?1 brothers ?2"
      res =  kb.traverse rules
      assert_include res.first["?2"], "Guille"
    end
  end

  def test_traverse_condition
    TmpFile.with_dir do |dir|
      kb = KnowledgeBase.new dir

      kb.register :brothers, datafile_test(:person).brothers, undirected: true
      kb.register :parents, datafile_test(:person).parents
      kb.register :marriages, datafile_test(:person).marriages, source: "=>Alias", target: "=>Alias"

      rules = []
      rules << "Miki parents ?1 - 'Type of parent=father'"
      entities, paths =  kb.traverse rules
      assert_equal entities["?1"], ["Juan"]
    end
  end

  def test_traverse_identify
    TmpFile.with_dir do |dir|
      kb = KnowledgeBase.new dir
      kb.entity_options = {"TestKnowledgeBaseQuery::Person" => {test: "Default"}}

      kb.register :brothers, datafile_test(:person).brothers, undirected: true
      kb.register :parents, datafile_test(:person).parents, entity_options: {"TestKnowledgeBaseQuery::Person" => {test: "Parents"}}

      rules = []
      rules << "001 brothers ?1"
      res =  kb.traverse rules
      assert_include res.first["?1"], "Isa"
    end
  end

  def test_traverse_target
    TmpFile.with_dir do |dir|
      kb = KnowledgeBase.new dir

      kb.register :brothers, datafile_test(:person).brothers, undirected: true
      kb.register :parents, datafile_test(:person).parents

      rules = []
      rules << "?target =brothers 001"
      rules << "?1 brothers ?target"
      res =  kb.traverse rules
      assert_include res.first["?1"], "Isa"
      assert_include res.first["?target"], "Miki"
    end
  end

  def test_traverse_translate_multiple
    TmpFile.with_dir do |dir|
      kb = KnowledgeBase.new dir

      kb.register :brothers, datafile_test(:person).brothers, undirected: true
      kb.register :parents, datafile_test(:person).parents
      kb.register :marriages, datafile_test(:person).marriages, undirected: true

      rules = []
      rules << "Guille brothers ?1"
      rules << "?2 =marriages ?1"
      rules << "?2 marriages ?3"
      entities, paths =  kb.traverse rules
      assert_include entities["?3"], "001"
    end
  end
end



#require File.join(File.expand_path(File.dirname(__FILE__)), '../..', 'test_helper.rb')
#require 'rbbt/knowledge_base/traverse'
#require 'rbbt/workflow'
#
#class TestKnowledgeBaseTraverse < Test::Unit::TestCase
#  def with_kb(&block)
#    keyword_test :organism do
#      require 'rbbt/sources/organism'
#      organism = Organism.default_code("Hsa")
#      TmpFile.with_file do |tmpdir|
#        kb = KnowledgeBase.new tmpdir
#        kb.namespace = organism
#        kb.format = {"Gene" => "Associated Gene Name"}
#
#        kb.register :gene_ages, datadir_test.gene_ages, :source => "=>Associated Gene Name"
#
#        kb.register :CollecTRI, datadir_test.CollecTRI, 
#          :source => "Transcription Factor=~Associated Gene Name", 
#          :target => "Target Gene=~Associated Gene Name",
#          :fields => ["[ExTRI] Confidence", "[ExTRI] PMID"]
#
#        yield kb
#      end
#    end
#  end
#
#  def test_traverse_simple
#    with_kb do |kb|
#      rules = []
#      rules << "SMAD4 gene_ages ?1"
#      res =  kb.traverse rules
#      assert_include res.first["?1"], "Bilateria"
#    end
#  end
#
#  def test_traverse_CollecTRI
#    with_kb do |kb|
#      rules = []
#      rules << "SMAD4 CollecTRI ?1 - '[ExTRI] Confidence=High'"
#      res =  kb.traverse rules
#      assert res.last.any?
#    end
#  end
#
#
#  def test_traverse
#    with_kb do |kb|
#      rules = []
#      rules << "?1 CollecTRI SMAD7"
#      rules << "?1 gene_ages ?2"
#      rules << "SMAD4 gene_ages ?2"
#      res =  kb.traverse rules
#      assert res.first["?1"].include? "MYC"
#    end
#  end
#
#  def test_target
#    with_kb do |kb|
#      rules = []
#      rules << "?target =CollecTRI SMAD7"
#      rules << "?1 CollecTRI ?target"
#      rules << "?1 gene_ages ?2"
#      rules << "SMAD4 gene_ages ?2"
#      res =  kb.traverse rules
#      assert res.first["?1"].include? "MYC"
#    end
#  end
#
#  def test_target_translate
#    with_kb do |kb|
#      rules = []
#      rules << "?target =CollecTRI ENSG00000101665"
#      rules << "?1 CollecTRI ?target"
#      res =  kb.traverse rules
#      assert res.first["?1"].include? "MYC"
#    end
#  end
#
#  def test_target_attribute
#    with_kb do |kb|
#      rules = []
#      rules << "?1 CollecTRI SMAD7"
#      all =  kb.traverse rules
#
#      rules = []
#      rules << "?1 CollecTRI SMAD7 - '[ExTRI] Confidence'=High"
#      low =  kb.traverse rules
#
#      assert low.last.length < all.last.length
#    end
#  end
#
#  def test_traverse_same_age
#    with_kb do |kb|
#      rules_str=<<-EOF
#?target1 =gene_ages SMAD7
#?target2 =gene_ages SMAD4
#?target1 gene_ages ?age
#?target2 gene_ages ?age
#?1 gene_ages ?age
#      EOF
#      rules = rules_str.split "\n"
#      res =  kb.traverse rules
#      assert_include res.first["?1"], "MET"
#    end
#  end
#
#  def test_traverse_same_age_acc
#    with_kb do |kb|
#      rules_str=<<-EOF
#?target1 =gene_ages SMAD7
#?target2 =gene_ages SMAD4
#?age{
#  ?target1 gene_ages ?age
#  ?target2 gene_ages ?age
#}
#?1 gene_ages ?age
#      EOF
#      rules = rules_str.split "\n"
#      res =  kb.traverse rules
#      assert_include res.first["?1"], "MET"
#    end
#  end
#
#  def test_wildcard_db
#    with_kb do |kb|
#      rules = []
#      rules << "SMAD4 ?db ?1"
#      res =  kb.traverse rules
#    end
#  end
#end
#
