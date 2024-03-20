require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')
require 'scout/tsv'

class TestAnnotationTSV < Test::Unit::TestCase
  module AnnotationClass
    extend Annotation

    annotation :code, :code2
  end

  def test_tsv
    str1 = "string1"
    str2 = "string2"
    AnnotationClass.setup(str1, :c11, :c12)
    AnnotationClass.setup(str2, :c21, :c22)

    assert_equal str1, Annotation.tsv([str1, str2], :all).tap{|t| t.unnamed = false}[str1.annotation_id + "#0"]["literal"] 
    assert_equal :c11, Annotation.tsv([str1, str2], :all).tap{|t| t.unnamed = false}[str1.annotation_id + "#0"]["code"] 
    assert_equal str2, Annotation.tsv([str1, str2], :all).tap{|t| t.unnamed = false}[str2.annotation_id + "#1"]["literal"] 
    assert_equal :c21, Annotation.tsv([str1, str2], :all).tap{|t| t.unnamed = false}[str2.annotation_id + "#1"]["code"] 
    assert_equal "c11", JSON.parse(Annotation.tsv([str1, str2], :code, :JSON).tap{|t| t.unnamed = false}[str1.annotation_id + "#0"]["JSON"])["code"]
  end

  def test_load_array_tsv
    str1 = "string1"
    str2 = "string2"
    AnnotationClass.setup(str1, :c11, :c12)
    AnnotationClass.setup(str2, :c21, :c22)

    tsv = Annotation.tsv([str1, str2], :all)

    list = Annotation.load_tsv(tsv)
    assert_equal [str1, str2], list
    assert_equal :c11, list.first.code
  end

  def test_load_extended_array_tsv
    str1 = "string1"
    str2 = "string2"
    a = [str1, str2]
    code = "Annotation String 2"
    AnnotationClass.setup(a, code)
    a.extend AnnotatedArray


    assert_equal code, Annotation.load_tsv(Annotation.tsv(a, :all)).code

    assert_equal str2, Annotation.load_tsv(Annotation.tsv(a, :literal, :JSON)).sort.last
  end
end

