require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestTSVAdapter < Test::Unit::TestCase
  def test_get_set
    tsv = TSV.setup({}, :type => :list, :key_field => "Key", :fields => %w(one two three))
    tsv.type = :list
    tsv.extend TSVAdapter
    tsv["a"] = %w(1 2 3)

    assert_equal %w(a), tsv.keys
    assert_equal [%w(1 2 3)], tsv.collect{|k,v| v }
    assert_equal [%w(1 2 3)], tsv.values

    json = tsv.to_json
    new = JSON.parse(json)
    tsv.annotate(new)
    new.extend TSVAdapter

    tsv = new
    assert_equal %w(a), tsv.keys
    assert_equal [%w(1 2 3)], tsv.collect{|k,v| v }
    assert_equal [%w(1 2 3)], tsv.values
    assert_equal [["a", %w(1 2 3)]], tsv.sort

    tsv["b"] = %w(11 22 33)
    assert_equal [["a", %w(1 2 3)], ["b", %w(11 22 33)]], tsv.sort
    assert_equal [["b", %w(11 22 33)], ["a", %w(1 2 3)]], tsv.sort_by{|k,v| -v[0].to_i }
  end

  def test_serializer
    tsv = TSV.setup({}, :type => :list, :key_field => "Key", :fields => %w(one two three))
    tsv.type = :list
    tsv.extend TSVAdapter
    tsv.serializer = :marshal
    tsv["a"] = [1, 2, 3]


    assert_equal [1, 2, 3], tsv["a"]
    assert_equal [1, 2, 3], Marshal.load(tsv.orig_get("a"))
  end
end

