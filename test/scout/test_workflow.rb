require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestWorkflow < Test::Unit::TestCase

  module Pantry
    extend Resource
    self.subdir = 'share/pantry'
    self.path_maps[:tmp] = TestWorkflow.tmpdir
    self.path_maps[:default] = :tmp
    self.map_order = [:tmp]

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
    extend Workflow

    helper :whisk do |eggs|
      "Whisking eggs from #{eggs}"
    end

    helper :mix do |base, mixer|
      "Mixing base (#{base}) with mixer (#{mixer})"
    end

    helper :bake do |batter|
      "Baking batter (#{batter})"
    end

    dep :prepare_batter
    task :bake_muffin_tray => :string do 
      bake(step(:prepare_batter).load)
    end

    dep :whisk_eggs
    input :add_bluberries, :boolean
    task :prepare_batter => :string do |add_bluberries|
      whisked_eggs = step(:whisk_eggs).load
      batter = mix(whisked_eggs, Pantry.flour.produce)

      if add_bluberries
        batter = mix(batter, Pantry.blueberries.produce) 
      end

      batter
    end

    task :whisk_eggs => :string do
      whisk(Pantry.eggs.produce)
    end
  end

  setup do
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
    assert_equal "Baking batter (Mixing base (Whisking eggs from share/pantry/eggs) with mixer (share/pantry/flour))",
      Baking.job(:bake_muffin_tray, "Normal muffin").run

    assert_equal "Baking batter (Mixing base (Mixing base (Whisking eggs from share/pantry/eggs) with mixer (share/pantry/flour)) with mixer (share/pantry/blueberries))",
      Baking.job(:bake_muffin_tray, "Blueberry muffin", :add_bluberries => true).run
  end
end
