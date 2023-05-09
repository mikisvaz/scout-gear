require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestMetaExtension < Test::Unit::TestCase
  module ExtensionClass
    extend MetaExtension

    extension_attr :code, :code2
  end

  def test_setup_annotate
    str = "String"
    ExtensionClass.setup(str, :code)
    assert ExtensionClass === str
    assert_equal :code, str.code

    str2 = "String2"
    str.annotate(str2)
    assert_equal :code, str2.code
  end

  def test_marshal
    str = "String"
    ExtensionClass.setup(str, :code)
    assert ExtensionClass === str
    assert_equal :code, str.code

    str2 = Marshal.load(Marshal.dump(str))
    assert_equal :code, str2.code
  end

  def test_setup_alternatives
    str = "String"

    ExtensionClass.setup(str, :code2 => :code)
    assert_equal :code, str.code2

    ExtensionClass.setup(str, code2: :code)
    assert_equal :code, str.code2

    ExtensionClass.setup(str, "code2" => :code)
    assert_equal :code, str.code2

  end

  def test_setup_block
    o = ExtensionClass.setup nil, :code => :c, :code2 => :c2 do
      puts 1
    end

    assert o.extension_attr_hash.include?(:code)
    assert o.extension_attr_hash.include?(:code2)
  end
end

