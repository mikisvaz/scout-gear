require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tsv'
require 'scout/annotation'

class TestAnnotationRepo < Test::Unit::TestCase
  module AnnotationClass
    extend Annotation

    annotation :code
  end

  def test_simple_annotation_nil

    TmpFile.with_file do |repo|
      annotation = Persist.annotation_repo_persist(repo, "My annotation nil") do
        nil
      end

      assert_nil annotation

      annotation = assert_nothing_raised do
        Persist.annotation_repo_persist(repo, "My annotation nil") do
          raise
        end
      end

      assert_nil annotation
    end
  end

  def test_simple_annotation_empty

    TmpFile.with_file do |repo|
      annotation = Persist.annotation_repo_persist(repo, "My annotation nil") do
        []
      end

      assert_empty annotation

      annotation = assert_nothing_raised do
        Persist.annotation_repo_persist(repo, "My annotation nil") do
          raise
        end
      end

      assert_empty annotation
    end
  end



  def test_simple_annotation

    TmpFile.with_file do |repo|
      annotation = Persist.annotation_repo_persist(repo, "My annotation simple") do
        AnnotationClass.setup("TESTANNOTATION", code: "test_code")
      end

      assert_equal "TESTANNOTATION", annotation
      assert_equal "test_code", annotation.code

      annotation = assert_nothing_raised do
        Persist.annotation_repo_persist(repo, "My annotation simple") do
          raise
        end
      end

      assert_equal "TESTANNOTATION", annotation
      assert_equal "test_code", annotation.code
    end
  end

  def test_array_with_annotation

    TmpFile.with_file do |repo|
      annotation = Persist.annotation_repo_persist(repo, "My annotation") do
        [
          AnnotationClass.setup("TESTANNOTATION", code: "test_code"),
          AnnotationClass.setup("TESTANNOTATION2", code: "test_code2")
        ]
      end.first

      assert_equal "TESTANNOTATION", annotation
      assert_equal "test_code", annotation.code

      annotation = assert_nothing_raised do
        Persist.annotation_repo_persist(repo, "My annotation") do
          raise
        end.last
      end

      assert_equal "TESTANNOTATION2", annotation
      assert_equal "test_code2", annotation.code
    end
  end

  def test_annotation_array

    TmpFile.with_file do |repo|
      annotation = Persist.annotation_repo_persist(repo, "My annotation array") do
        a = AnnotationClass.setup(["TESTANNOTATION", "TESTANNOTATION2"], code: "test_code")
        a.extend AnnotatedArray
        a
      end.first

      assert_equal "TESTANNOTATION", annotation
      assert_equal "test_code", annotation.code

      annotation = assert_nothing_raised do
        Persist.annotation_repo_persist(repo, "My annotation array") do
          raise
        end.last
      end

      assert_equal "TESTANNOTATION2", annotation
      assert_equal "test_code", annotation.code
    end
  end

  def test_annotation_array_with_fields

    TmpFile.with_file do |repo_file|
      repo = Persist.open_tokyocabinet(repo_file, false, :list, :BDB)
      TSV.setup(repo, :fields => ["literal", "annotation_types", "code"], :key_field => "Annotation ID", type: :list)
      repo.extend TSVAdapter

      annotation = Persist.annotation_repo_persist(repo, "My annotation array") do
        a = AnnotationClass.setup(["TESTANNOTATION", "TESTANNOTATION2"], code: "test_code")
        a.extend AnnotatedArray
        a
      end.first

      assert_equal "TESTANNOTATION", annotation
      assert_equal "test_code", annotation.code

      repo = Persist.open_tokyocabinet(repo_file, false, :list, :BDB)
      annotation2 = assert_nothing_raised do
        Persist.annotation_repo_persist(repo, "My annotation array") do
          raise
        end.last
      end

      assert_equal "TESTANNOTATION2", annotation2
      assert_equal "test_code", annotation2.code
    end
  end
end

