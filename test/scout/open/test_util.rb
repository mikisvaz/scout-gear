require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/open'

class TestOpenUtil < Test::Unit::TestCase
  def test_read_grep
    content =<<-EOF
1
2
3
4
    EOF
    TmpFile.with_file(content) do |file|
      sum = 0
      Open.read(file, :grep => '^1\|3') do |line| sum += line.to_i end
      assert_equal(1 + 3, sum)
    end

    TmpFile.with_file(content) do |file|
      sum = 0
      Open.read(file, :grep => ["1","3"]) do |line| sum += line.to_i end
      assert_equal(1 + 3, sum)
    end
  end

  def test_read_grep_invert
    content =<<-EOF
1
2
3
4
    EOF
    TmpFile.with_file(content) do |file|
      sum = 0
      Open.read(file, :grep => '^1\|3', :invert_grep => true) do |line| sum += line.to_i end
      assert_equal(2 + 4, sum)
    end

    TmpFile.with_file(content) do |file|
      sum = 0
      Open.read(file, :grep => ["1","3"]) do |line| sum += line.to_i end
      assert_equal(1 + 3, sum)
    end
  end
end

