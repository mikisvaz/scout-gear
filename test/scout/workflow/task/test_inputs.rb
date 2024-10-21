require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/workflow'

class TestTaskInput < Test::Unit::TestCase
  def example_workflow
    Workflow.annonymous_workflow do
      input :string, :string, "", "String"
      input :integer, :integer, "", 1
      input :float, :float, "", 1.1
      input :boolean, :boolean, "", false
      input :array, :array, "", %w(a b)
      input :path, :path, "", "dir/subdir/file"
      input :file, :file, ""
      input :integer_array, :integer_array, "", [1, 2]
      input :float_array, :float_array, "", [1.1, 2.2]
      input :boolean_array, :boolean_array, "", [true, false, true]
      input :path_array, :path_array, "", %w(dir/subdir/file1 dir/subdir/file2)
      input :file_array, :file_array
      task :task => :array do
        inputs
      end

      dep :task
      task :task2 => :array do
        inputs
      end
    end
  end

  def example_task
    example_workflow.tasks[:task]
  end

  def test_assign_inputs
    task = self.example_task

    assert_equal [:integer], task.assign_inputs(:string => "String", :integer => 2, :integer_array => %w(1 2))[1]
    
    TmpFile.with_file("1\n2") do |integer_array_file|
      assert_equal [:integer], task.assign_inputs(:string => "String", :integer => 2, :integer_array => integer_array_file)[1]
    end
  end

  def test_boolean
    task = self.example_task

    assert_equal [:boolean], task.assign_inputs(:string => "String", :integer => 1, :boolean => true)[1]

    TmpFile.with_file("1\n2") do |integer_array_file|
      Open.open(integer_array_file) do |f|
        inputs, _ = task.assign_inputs(:string => "String", :integer => 2, :integer_array => f)
        input_pos = task.inputs.index{|p| p.first == :integer_array}
        assert File === inputs[input_pos]
      end
    end
  end

  def test_keep_stream
    task = self.example_task

    assert_equal [:integer], task.assign_inputs(:string => "String", :integer => 2, :integer_array => %w(1 2))[1]

    TmpFile.with_file("1\n2") do |integer_array_file|
      Open.open(integer_array_file) do |f|
        inputs, _ = task.assign_inputs(:string => "String", :integer => 2, :integer_array => f)
        input_pos = task.inputs.index{|p| p.first == :integer_array}
        assert File === inputs[input_pos]
      end
    end
  end


  def test_digest_inputs
    task = self.example_task

    TmpFile.with_file("2\n3") do |integer_array_file|
      assert_equal task.process_inputs(:string => "String", :integer => 2, :integer_array => %w(2 3))[1],
        task.process_inputs(:string => "String", :integer => 2, :integer_array => integer_array_file)[1]
    end
  end

  def test_digest_stream
    task = self.example_task

    assert_equal [:integer], task.assign_inputs(:string => "String", :integer => 2, :integer_array => %w(1 2))[1]

    TmpFile.with_file("1\n2") do |integer_array_file|
      hash1 = Open.open(integer_array_file) do |f|
        task.process_inputs(:string => "String", :integer => 2, :integer_array => f).last
      end
      hash2 = Open.open(integer_array_file) do |f|
        task.process_inputs(:string => "String", :integer => 2, :integer_array => f).last
      end
      assert_equal hash1, hash2
    end
  end



  def test_digest_file
    task = self.example_task

    TmpFile.with_file("2\n3") do |integer_array_file|
      assert_equal task.process_inputs(:string => "String", :integer => 2, :integer_array => %w(2 3)).last,
        task.process_inputs(:string => "String", :integer => 2, :integer_array => integer_array_file).last
    end
  end

  def test_save_and_load
    task = self.example_task

    TmpFile.with_file("2\n3") do |integer_array_file|
      inputs = {:string => "String", :integer => 2, :integer_array => integer_array_file, :float_array => %w(1.1 2.2)}
      original_digest =  task.process_inputs(inputs).last

      TmpFile.with_file do |save_directory|
        task.save_inputs(save_directory, inputs)
        new_inputs = task.load_inputs(save_directory)
        new_digest =  task.process_inputs(new_inputs).last
        assert_equal original_digest, new_digest
      end
    end
  end

  def test_save_and_load_file
    task = self.example_task

    TmpFile.with_file("TEST") do |somefile|
      inputs = {:string => "String", :integer => 2, :file => somefile, :float_array => %w(1.1 2.2)}
      original_digest =  task.process_inputs(inputs).last

      TmpFile.with_file do |save_directory|
        task.save_inputs(save_directory, inputs)
        Open.rm somefile
        new_inputs = task.load_inputs(save_directory)
        new_digest =  task.process_inputs(new_inputs).last
        assert_equal original_digest, new_digest
      end
    end
  end

  def test_save_and_load_file_with_copy
    task = self.example_task

    TmpFile.with_file("TEST") do |somefile|
      inputs = {:string => "String", :integer => 2, :file => somefile, :float_array => %w(1.1 2.2)}
      original_digest =  task.process_inputs(inputs).last

      TmpFile.with_file do |save_directory|
        task.save_inputs(save_directory, inputs)
        TmpFile.with_file do |copy_directory|
          Open.cp save_directory, copy_directory
          Open.rm_rf save_directory
          new_inputs = task.load_inputs(copy_directory)
          new_digest =  task.process_inputs(new_inputs).last
          assert_equal original_digest, new_digest
        end
      end
    end
  end


  def test_save_and_load_file_array
    task = self.example_task

    TmpFile.with_file do |dir|
      file1 = File.join(dir, 'subdir1/file')
      file2 = File.join(dir, 'subdir2/file')

      Open.write(file1, "TEST1")
      Open.write(file2, "TEST2")
      inputs = {:string => "String", :integer => 2, :file_array => [file1, file2], :float_array => %w(1.1 2.2)}
      original_digest =  task.process_inputs(inputs).last

      TmpFile.with_file do |save_directory|
        task.save_inputs(save_directory, inputs)
        Open.rm(file1)
        Open.rm(file2)
        new_inputs = task.load_inputs(save_directory)
        new_digest =  task.process_inputs(new_inputs).last
        assert_equal original_digest, new_digest
      end
    end
  end

  def test_save_and_load_file_array_task2
    task = self.example_workflow.tasks[:task2]

    TmpFile.with_file do |dir|
      file1 = File.join(dir, 'subdir1/file')
      file2 = File.join(dir, 'subdir2/file')

      Open.write(file1, "TEST1")
      Open.write(file2, "TEST2")
      inputs = {:string => "String", :integer => 2, :file_array => [file1, file2], :float_array => %w(1.1 2.2)}
      original_digest =  task.process_inputs(inputs).last

      TmpFile.with_file do |save_directory|
        task.save_inputs(save_directory, inputs)
        Open.rm(file1)
        Open.rm(file2)
        new_inputs = task.load_inputs(save_directory)
        new_digest =  task.process_inputs(new_inputs).last
        assert_equal original_digest, new_digest
      end
    end
  end

  def test_save_and_load_array_from_file
    task = self.example_workflow.tasks[:task]

    TmpFile.with_file do |dir|
      array = %w(1 2 3 4 5)
      file1 = File.join(dir, 'subdir1/file')
      Open.write(file1, array * "\n")
      inputs = {:array => file1 }
      original_digest =  task.process_inputs(inputs).last

      TmpFile.with_file do |save_directory|
        task.save_inputs(save_directory, inputs)
        Open.rm(file1)
        new_inputs = task.load_inputs(save_directory)
        new_digest =  task.process_inputs(new_inputs).last
        assert_equal original_digest, new_digest
      end
    end
  end

  def test_recursive_inputs
    w = Module.new do
      extend Workflow

      self.name = "SaluteWF"

      input :name, :string
      task :salute => :string do |name|
        "Hi #{name}"
      end

      task_alias :salute_miguel, self, :salute, :name => "Miguel"
    end

    assert w.tasks[:salute_miguel].recursive_inputs.empty?
  end

  def test_recursive_inputs_with_overriden_deps
    w = Module.new do
      extend Workflow

      self.name = "SaluteWF"

      input :name, :string
      task :salute => :string do |name|
        "Hi #{name}"
      end

      task_alias :salute_miguel, self, :salute, :name => "Miguel"

      dep :salute
      task :repeat_salute => :array do
        [step(:salute).load] * 3
      end

      dep :salute_miguel
      task_alias :repeat_salute_miguel, self, :repeat_salute, "SaluteWF#salute" => :salute_miguel
    end

    assert_equal ["Hi Miguel"] * 3, w.job(:repeat_salute_miguel).run

    assert w.tasks[:repeat_salute_miguel].recursive_inputs.empty?
  end
end
