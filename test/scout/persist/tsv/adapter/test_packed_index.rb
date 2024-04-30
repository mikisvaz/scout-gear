require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestClass < Test::Unit::TestCase
  def test_open
    TmpFile.with_file do |tmpfile|
      pi = Persist.open_pki tmpfile, true, %w(i i 23s f f f f f)
      100.times do |i|
        pi << [i, i+2, i.to_s * 10, rand, rand, rand, rand, rand]
      end
      pi << nil
      pi << nil
      pi.close

      TSV.setup(pi, :key_field => "Number", :fields => %w(i i2 s f1 f2 f3 f4 f5), :type => :list)

      pi = PackedIndex.new(tmpfile, false)
      100.times do |i|
        assert_equal i, pi[i][0] 
        assert_equal i+2, pi[i][1] 
      end
      assert_equal nil, pi[100]
      assert_equal nil, pi[101]

      pi = Persist.open_pki tmpfile, false, %w(i i 23s f f f f f)
      100.times do |i|
        assert_equal i, pi[i][0] 
        assert_equal i+2, pi[i][1] 
      end
      assert_equal nil, pi[100]
      assert_equal nil, pi[101]

      assert_equal "Number", pi.key_field
    end
  end
end

