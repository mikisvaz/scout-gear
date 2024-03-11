require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')
require 'scout/tsv'

class TestMetaExtensionTSV < Test::Unit::TestCase
  module ExtensionClass
    extend MetaExtension

    extension_attr :code, :code2
  end

  def test_tsv
    str1 = "string1"
    str2 = "string2"
    ExtensionClass.setup(str1, :c11, :c12)
    ExtensionClass.setup(str2, :c21, :c22)

    assert_equal str1, MetaExtension.tsv([str1, str2], :all).tap{|t| t.unnamed = false}[str1.extended_digest + "#0"]["literal"] 
    assert_equal :c11, MetaExtension.tsv([str1, str2], :all).tap{|t| t.unnamed = false}[str1.extended_digest + "#0"]["code"] 
    assert_equal str2, MetaExtension.tsv([str1, str2], :all).tap{|t| t.unnamed = false}[str2.extended_digest + "#1"]["literal"] 
    assert_equal :c21, MetaExtension.tsv([str1, str2], :all).tap{|t| t.unnamed = false}[str2.extended_digest + "#1"]["code"] 
    assert_equal "c11", JSON.parse(MetaExtension.tsv([str1, str2], :code, :JSON).tap{|t| t.unnamed = false}[str1.extended_digest + "#0"]["JSON"])["code"]
  end

  def test_load_array_tsv
    str1 = "string1"
    str2 = "string2"
    ExtensionClass.setup(str1, :c11, :c12)
    ExtensionClass.setup(str2, :c21, :c22)

    tsv = MetaExtension.tsv([str1, str2], :all)

    list = MetaExtension.load_tsv(tsv)
    assert_equal [str1, str2], list
    assert_equal :c11, list.first.code
  end

  def test_load_extended_array_tsv
    str1 = "string1"
    str2 = "string2"
    a = [str1, str2]
    code = "Annotation String 2"
    ExtensionClass.setup(a, code)
    a.extend ExtendedArray


    assert_equal code, MetaExtension.load_tsv(MetaExtension.tsv(a, :all)).code

    assert_equal str2, MetaExtension.load_tsv(MetaExtension.tsv(a, :literal, :JSON)).sort.last
  end
end

