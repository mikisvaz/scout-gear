require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestStepArchive < Test::Unit::TestCase
  def test_archive
    m = Module.new do
      extend Workflow
      self.name = "TestWF"

      input :option1
      task :step1 do end

      dep :step1
      input :option2
      task :step2 do end
    end

    job = m.job(:step2, option1: "Option1", option2: "Option2")
    job.run
    job.archive_deps
    assert_include job.archived_info, job.step(:step1).path
    assert_equal :done, job.archived_info[job.step(:step1).path][:status]

    assert_equal "Option1", job.archived_inputs[:option1]
    assert_equal "Option1", job.inputs.concat(job.archived_inputs)[:option1]
  end
end

