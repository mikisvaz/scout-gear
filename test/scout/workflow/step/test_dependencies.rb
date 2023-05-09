require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/named_array'
class TestStepDependencies < Test::Unit::TestCase
  def test_recursive_inputs
    tmpfile = tmpdir.test_step
    step1 = Step.new tmpfile.step1, NamedArray.setup(["12"], %w(input1)) do |s|
      s.length
    end

    step2 = Step.new tmpfile.step2, NamedArray.setup([2], %w(input2)) do |times|
      step1 = dependencies.first
      (step1.inputs.first + " has " + step1.load.to_s + " characters") * times
    end

    step2.dependencies = [step1]

    assert_equal 2, step2.inputs["input2"]
    assert_equal "12", step2.recursive_inputs["input1"]
    assert_equal 2, step2.inputs[:input2]
    assert_equal "12", step2.recursive_inputs[:input1]
  end
end

