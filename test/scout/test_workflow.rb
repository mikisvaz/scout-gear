require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestWorkflow < Test::Unit::TestCase

  module Pantry
    extend Resource
    self.subdir = 'share/pantry'

    Pantry.claim Pantry.eggs, :proc do
      Log.info "Buying Eggs in the store"
      "Eggs"
    end

    Pantry.claim Pantry.flour, :proc do
      Log.info "Buying Flour in the store"
      "Flour"
    end

    Pantry.claim Pantry.blueberries, :proc do
      Log.info "Buying Bluberries in the store"
      "Bluberries"
    end
  end

  module Baking
    def self.whisk(eggs)
      "Whisking eggs from #{eggs}"
    end

    def self.mix(base, mixer)
      "Mixing base (#{base}) with mixer (#{mixer})"
    end

    def self.bake(batter)
      "Baking batter (#{batter})"
    end
  end

  module Baking
    extend Workflow

    dep :prepare_batter
    task :bake_muffin_tray => :string do 
      Baking.bake(step(:prepare_batter).load)
    end

    dep :whisk_eggs
    input :add_bluberries, :boolean
    task :prepare_batter => :string do |add_bluberries|
      whisked_eggs = step(:whisk_eggs).load
      batter = Baking.mix(whisked_eggs, Pantry.flour.produce)

      if add_bluberries
        batter = Baking.mix(batter, Pantry.blueberries.produce) 
      end

      batter
    end

    task :whisk_eggs => :string do
      Baking.whisk(Pantry.eggs.produce)
    end
  end


  def setup
    Baking.directory = tmpdir.var.jobs.baking.find
  end

  def test_task
    wf = Workflow.annonymous_workflow do
      task :length => :integer do
        self.length
      end
    end
    bindings = "12345"
    assert_equal 5, wf.tasks[:length].exec_on(bindings)
  end

  def test_baking
    Log.severity = 0
    assert_equal "Baking batter (Mixing base (Mixing base (Whisking eggs from share/pantry/eggs) with mixer (share/pantry/flour)) with mixer (share/pantry/blueberries))",
      Baking.job(:bake_muffin_tray, :add_bluberries => true).run

    assert_equal "Baking batter (Mixing base (Whisking eggs from share/pantry/eggs) with mixer (share/pantry/flour))",
      Baking.job(:bake_muffin_tray).run

  end

end
