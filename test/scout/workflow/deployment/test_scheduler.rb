require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/workflow/deployment/scheduler/slurm'

class TestScheduler < Test::Unit::TestCase
  setup do
    module TestWF
      extend Workflow
      self.name = "TestWF"

      MULT ||= 0.1
      task :a => :text do
        sleep(TestWF::MULT * (rand(10) + 2))
      end

      dep :a
      task :b => :text do
        sleep(TestWF::MULT * (rand(10) + 2))
      end

      dep :a
      dep :b
      task :c => :text do
        sleep(TestWF::MULT * (rand(10) + 2))
      end

      dep :c
      task :d => :text do
        sleep(TestWF::MULT * (rand(10) + 2))
      end

      dep :c
      task :e => :text do
        sleep(TestWF::MULT * (rand(10) + 2))
      end
    end
  end

  def test_orchestrate_process

    jobs =[]

    num = 1
    num.times do |i|
      jobs.concat %w(TEST1 TEST2).collect{|name| TestWF.job(:d, name + " #{i}") }
    end
    jobs.each do |j| j.recursive_clean end

    rules = YAML.load <<-EOF
defaults:
  log: 4
default_resources:
  IO: 1
TestWF:
  a:
    resources:
      cpus: 7
  b:
    resources:
      cpus: 2
  c:
    resources:
      cpus: 10
  d:
    resources:
      cpus: 15
    EOF

    batches = Workflow::Orchestrator.job_batches(rules, jobs)
    dirs = Workflow::Scheduler.process_batches(batches, dry_run: true)
  end
end

