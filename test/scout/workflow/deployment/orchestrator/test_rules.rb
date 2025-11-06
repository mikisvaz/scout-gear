require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestOrchestrateRules < Test::Unit::TestCase

  RULES = IndiferentHash.setup(YAML.load(<<-EOF))
---
defaults:
  queue: first_queue
  time: 1h
  log: 2
  config_keys: key1 value1 token1
chains:
  chain_a:
    workflow: TestWFA
    tasks: a1, a2, a3
    config_keys: key2 value2 token2, key3 value3 token3.1 token3.2
  chain_b:
    workflow: TestWFB
    tasks: b1, b2
  chain_b2:
    comment: This chain is not valid, it is missing a2
    tasks: TestWFA#a1, TestWFA#a3, TestWFB#b1, TestWFB#b2
TestWFA:
  defaults:
    log: 4
    config_keys: key4 value4 token4
  a1:
    cpus: 10
    config_keys: key5 value5 token5
TestWFC:
  defaults:
    skip: true
    log: 4
  EOF

  def test_defaults
    rules = Workflow::Orchestrator.task_specific_rules RULES, "TestWFA", :a1
    assert_equal "first_queue" , rules[:queue]
  end


  def test_task_options
    rules = Workflow::Orchestrator.task_specific_rules RULES, "TestWFA", :a1
    assert_equal 10, rules[:cpus]
    assert_equal 4, rules[:log]
  end

  def test_skip
    rules = Workflow::Orchestrator.task_specific_rules RULES, "TestWFC", :c1
    assert rules[:skip]
  end

  def test_load_rules
    rules1 =<<-EOF
defaults:
  name: rules1
  time: 1h
  cpus: 2
Workflow:
  defaults:
    time: 1m
    cpus: 4
Workflow3:
  defaults:
    time: 3m
    EOF

    rules2 =<<-EOF
defaults:
  name: rules2
  time: 2h
Workflow:
  defaults:
    time: 2m
Workflow2:
  defaults:
    time: 3m
    EOF

    TmpFile.with_file rules1 do |file1|
      TmpFile.with_file rules2 do |file2|

        rules = Workflow::Orchestrator.load_rules [file2, file1]

        assert_equal 'rules2', rules[:defaults][:name]

        assert_equal 2, rules[:defaults][:cpus]
        assert_equal '2h', rules[:defaults][:time]

        assert_equal 4, rules['Workflow'][:defaults][:cpus]
        assert_equal '2m', rules["Workflow"][:defaults][:time]

        assert_include rules, 'Workflow2'
        assert_include rules, 'Workflow3'
      end
    end
  end

  def test_load_rules_config_keys
    rules1 =<<-EOF
Workflow:
  defaults:
    time: 1h
    cpus: 2
    config_keys: cpus 4 loop
    EOF

    rules2 =<<-EOF
Workflow:
  defaults:
    time: 1h
    cpus: 4
    config_keys: mem high database
    EOF

    correct = YAML.load <<-EOF
---
Workflow:
  defaults:
    time: 1h
    cpus: 4
    config_keys: cpus 4 loop,mem high database
    EOF


    TmpFile.with_file rules1 do |file1|
      TmpFile.with_file rules2 do |file2|

        rules = Workflow::Orchestrator.load_rules [file2, file1]
        assert_equal correct, rules
      end
    end
  end


  def test_load_rules_config_keys_alt
    rules1 =<<-EOF
Workflow:
  defaults:
    name: rules1
    time: 1h
    cpus: 2
    config_keys:
      - cpus 4 loop
      - level warn log
    EOF

    rules2 =<<-EOF
Workflow:
  defaults:
    name: rules2
    time: 1h
    cpus: 4
    config_keys:
      - mem high database
    EOF

    correct = YAML.load <<-EOF
---
Workflow:
  defaults:
    name: rules2
    time: 1h
    cpus: 4
    config_keys: cpus 4 loop,level warn log,mem high database
    EOF


    TmpFile.with_file rules1 do |file1|
      TmpFile.with_file rules2 do |file2|

        rules = Workflow::Orchestrator.load_rules [file2, file1]
        assert_equal correct, rules
      end
    end
  end


  def test_load_rules_import
    rules1 =<<-EOF
Workflow:
  defaults:
    time: 1h
    cpus: 2
    config_keys: cpus 4 loop
    EOF

    rules2 =<<-EOF
Workflow:
  defaults:
    time: 1h
    cpus: 2
    config_keys: mem high database
    EOF

    correct = YAML.load <<-EOF
---
Workflow:
  defaults:
    time: 1h
    cpus: 2
    config_keys: cpus 4 loop,mem high database
    EOF


    TmpFile.with_file rules1 do |file1|
      TmpFile.with_file rules2 do |file2|
        Open.open(file2, mode: 'a') do |f|
          f.puts "import: #{file1}"
        end

        rules = Workflow::Orchestrator.load_rules file2
        assert_equal correct, rules
      end
    end
  end
end

