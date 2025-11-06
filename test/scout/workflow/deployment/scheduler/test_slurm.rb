require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

# Define a small workflow used by tests
module TestSchedWF
  extend Workflow

  task :a1 => :string do self.task_name.to_s end

  dep :a1
  task :b1 => :string do self.task_name.to_s end
end

class TestSchedulerJobSLURM < Test::Unit::TestCase
  def test_basic_template
    job = TestSchedWF.job(:b1, "TEST")
    TmpFile.with_file do |batch_dir|
      tpl = SLURM.job_template(job, :batch_dir => batch_dir, :lua_modules => 'java')
      assert_include tpl, 'module load java'
      assert_include tpl, '#STEP_PATH'
      assert_include tpl, '#SBATCH'
    end
  end

  def test_singularity
    job = TestSchedWF.job(:b1, "TEST")
    TmpFile.with_file do |batch_dir|
      tpl = SLURM.job_template(job, :batch_dir => batch_dir, :singularity => true, :singularity_img => '/tmp/img.sif')
      assert_include tpl, 'singularity exec'
    end
  end
end
