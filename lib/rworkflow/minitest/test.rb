module Rworkflow
  module Minitest
    # Include in your test classes to add functionality for worker and workflow tests
    module Test
      def setup
        super
        rworkflow_setup
      end

      def teardown
        super
        rworkflow_teardown
      end

      def rworkflow_setup
      end
      protected :rworkflow_setup

      def rworkflow_teardown
      end
      protected :rworkflow_teardown

      # @params [Class] the worker class to instantiate
      # @params [Hash] options hash
      # @option [Class] :flow workflow class to instantiate; defaults to SidekiqFlow
      # @option [Class] :name the state name
      def rworkflow_worker(worker_class, flow: ::SidekiqFlow, name: nil, meta: {})
        name ||= worker_class.name
        worker = worker_class.new
        workflow = flow.new(name)
        meta.each { |key, value| workflow.set(key, value) }

        worker.instance_variable_set(:@workflow, workflow)
        worker.instance_variable_set(:@state_name, name)

        workflow.extend(WorkerUnitTestFlow)
        if defined?(flexmock)
          flexmock(workflow.class).should_receive(:terminal?).and_return(true)
        end

        yield(workflow) if block_given?

        return worker, workflow
      end
    end

    module WorkerUnitTestFlow
      def transition(_, name, objects)
        push(objects, name)
      end
    end
  end
end
