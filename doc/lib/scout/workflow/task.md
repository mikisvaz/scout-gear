Task
====

```ruby
    wf = Workflow.annonymous_workflow "TaskInputs" do
      input :input1, :integer
      task :step1 => :integer do |i| i end

      dep :step1
      input :input2, :integer, "Integer", 3
      task :step2 => :integer do |i| i * step(:step1).load end
    end
```
