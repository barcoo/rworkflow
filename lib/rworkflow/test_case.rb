module Rworkflow
  module TestCase
    def workflow_setup
    end

    def workflow_teardown
    end

    def workflow_disable_push_back!
      Rworkflow::Worker.descendants.each do |klass|
        flexmock(klass).new_instances.should_receive(:push_back).and_return(nil)
      end
    end
  end
end
