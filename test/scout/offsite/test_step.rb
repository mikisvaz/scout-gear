require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestOffsiteStep < Test::Unit::TestCase
  def test_offsite_task
    workflow_code =<<-EOF
module TestWF
  extend Workflow

  input :string, :string, "String", "string"
  task :string => :string do |string| string end
end

TestWF.directory = Path.setup("#{tmpdir.offsite.TestWF}")
    EOF

    TmpFile.with_file workflow_code, :extension => 'rb' do |wffile|
      wf = Workflow.require_workflow wffile

      job = wf.job(:string)

      off = OffsiteStep.setup job, server: 'localhost', workflow_name: wffile

      refute off.done?
      assert_equal 'string', off.run

      assert off.done?
      assert_equal 'string', off.run
    end
  end
end

