require 'test_helper'

module Rworkflow
  class FlowTest < ActiveSupport::TestCase
    def setup
      super
      RedisRds::Object.flushdb
    end

    def test_workflow
      lifecycle = Lifecycle.new do |lc|
        lc.state('State1', cardinality: 2) do |state|
          state.transition :pushed, Flow::STATE_SUCCESSFUL
          state.transition :failed, Flow::STATE_FAILED
        end

        lc.initial = 'State1'
      end
      initial_objects = [1, 2, 3]
      workflow = Flow.create(lifecycle, 'myWorkflow')
      workflow_id = workflow.id

      assert Flow.registered?(workflow)

      workflow.start(initial_objects)
      workflow = Flow.new(workflow_id)
      assert !workflow.finished?

      workflow.fetch(1, 'State1') do |objects|
        assert_equal 2, objects.size
        assert_equal (objects & initial_objects), objects
        assert !workflow.finished?
        workflow.transition('State1', :pushed, objects.first)
        workflow.transition('State1', :failed, objects.second)
      end

      assert !workflow.finished?

      workflow.fetch(2, 'State1') do |last|
        assert_equal 1, last.size
        assert_equal (last & initial_objects), last
        assert !workflow.finished?
        workflow.transition('State1', :pushed, last.first)
      end

      assert workflow.finished?
      counters = workflow.counters
      assert_equal 2, counters[Flow::STATE_SUCCESSFUL]
      assert_equal 1, counters[Flow::STATE_FAILED]

      assert_equal [1, 3], workflow.list_objects(Flow::STATE_SUCCESSFUL)
    end

    def test_flow_cardinality_all_started
      lifecycle = Lifecycle.new do |lc|
        lc.state('State1', cardinality: Lifecycle::CARDINALITY_ALL_STARTED) do |state|
          state.transition :pushed, Flow::STATE_SUCCESSFUL
          state.transition :failed, Flow::STATE_FAILED
        end

        lc.initial = 'State1'
      end

      initial_objects = (1..6).to_a
      workflow = Flow.create(lifecycle, 'myWorkflow')
      workflow.start(initial_objects)
      workflow.fetch(1, 'State1') do |objects|
        assert_equal initial_objects.size, objects.size, 'The flow should fetch the number of objects given at the start'
      end
    end

    def test_flow_state_policy_wait
      initial_objects = [1, 2, 3, 4]
      lifecycle = Lifecycle.new do |lc|
        lc.state('InitState', cardinality: 1) do |state|
          state.transition :pushed, 'WaitState'
        end

        lc.state('WaitState', cardinality: initial_objects.size, policy: State::STATE_POLICY_WAIT) do |state|
          state.transition :collected, Flow::STATE_SUCCESSFUL
        end

        lc.initial = 'InitState'
      end

      workflow = Flow.create(lifecycle, 'myWorkflow')
      workflow.start(initial_objects)

      (initial_objects.size - 1).times do
        workflow.fetch(1, 'InitState') do |objects|
          assert_equal 1, objects.size, 'The flow should fetch the number of objects corresponding to the state cardinality'
          workflow.transition('InitState', :pushed, objects)
        end
      end

      workflow.fetch(1, 'WaitState') do |_objects|
        # This block should not be executed
        assert false, 'The collector state should not be executed until there is enough waiting objects (>= cardinality)'
      end

      # Lat object push in the initial state
      workflow.fetch(1, 'InitState') do |objects|
        assert_equal 1, objects.size, 'The flow should fetch the number of objects corresponding to the state cardinality'
        workflow.transition('InitState', :pushed, objects)
      end

      workflow.fetch(1, 'WaitState') do |objects|
        assert_equal initial_objects.size, objects.size, 'The flow should fetch the number of objects given at the start'
      end
    end
  end
end
