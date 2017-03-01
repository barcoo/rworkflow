require 'test_helper'

module Rworkflow
  class SidekiqFlowTest < ActiveSupport::TestCase
    def setup
      super
      RedisRds::Object.flushdb
    end

    def test_lethal_workflow
      lifecycle = Lifecycle.new do |lc|
        lc.state('Rworkflow::SidekiqFlowTest::Floating', cardinality: 10) do |state|
          state.transition :rescued, 'Rworkflow::SidekiqFlowTest::Lifeboat'
          state.transition :drowned, Rworkflow::Flow::STATE_FAILED
        end
        lc.state('Rworkflow::SidekiqFlowTest::Lifeboat', cardinality: 2) do |state|
          state.transition :landed, 'Rworkflow::SidekiqFlowTest::Land'
          state.transition :starved, Rworkflow::Flow::STATE_FAILED
        end
        lc.state('Rworkflow::SidekiqFlowTest::Land') do |state|
          state.transition :rescued, Rworkflow::Flow::STATE_SUCCESSFUL
          state.transition :died, Rworkflow::Flow::STATE_FAILED
        end

        lc.initial = 'Rworkflow::SidekiqFlowTest::Floating'
      end

      initial_objects = (0...20).to_a
      workflow = SidekiqFlow.create(lifecycle, 'Lethal Rworkflow 2: Lethaler', {})
      workflow.start(initial_objects)

      assert workflow.finished?
      counters = workflow.get_counters
      assert_equal 19, counters[Rworkflow::Flow::STATE_FAILED]
      assert_equal 1, counters[Rworkflow::Flow::STATE_SUCCESSFUL]

      assert 2, RedisRds::String.new('Rworkflow::SidekiqFlowTest::Floating').get.to_i
      assert 6, RedisRds::String.new('Rworkflow::SidekiqFlowTest::Lifeboat').get.to_i
      assert 2, RedisRds::String.new('Rworkflow::SidekiqFlowTest::Land').get.to_i
    end

    def test_pause_continue
      lifecycle = Lifecycle.new do |lc|
        lc.state('Rworkflow::SidekiqFlowTest::Floating', cardinality: 10) do |state|
          state.transition :rescued, 'Rworkflow::SidekiqFlowTest::Lifeboat'
          state.transition :drowned, Rworkflow::Flow::STATE_FAILED
        end
        lc.state('Rworkflow::SidekiqFlowTest::Lifeboat', cardinality: 2) do |state|
          state.transition :landed, Rworkflow::Flow::STATE_SUCCESSFUL
          state.transition :starved, Rworkflow::Flow::STATE_FAILED
        end

        lc.initial = 'Rworkflow::SidekiqFlowTest::Floating'
      end

      initial_objects = (0...20).to_a
      workflow = SidekiqFlow.create(lifecycle, 'Lethal Workflow 4: Lethalerest', {})

      workflow.pause
      workflow.start(initial_objects)
      assert !workflow.finished?
      workflow.pause
      workflow.continue
      assert !workflow.finished?
      workflow.continue
      assert workflow.finished?

      counters = workflow.get_counters
      assert_equal 18, counters[Rworkflow::Flow::STATE_FAILED]
      assert_equal 2, counters[Rworkflow::Flow::STATE_SUCCESSFUL]

      assert 2, RedisRds::String.new('Rworkflow::SidekiqFlowTest::Floating').get.to_i
      assert 6, RedisRds::String.new('Rworkflow::SidekiqFlowTest::Lifeboat').get.to_i
    end

    def test_collector_state_workflow
      lifecycle = Lifecycle.new do |lc|
        lc.state('Rworkflow::SidekiqFlowTest::PostcardSend', cardinality: 1) do |state|
          state.transition :sent, 'Rworkflow::SidekiqFlowTest::PostcardCollector'
        end

        lc.state('Rworkflow::SidekiqFlowTest::PostcardCollector', cardinality: Lifecycle::CARDINALITY_ALL_STARTED, policy: State::STATE_POLICY_WAIT) do |state|
          state.transition :received, Rworkflow::Flow::STATE_SUCCESSFUL
        end

        lc.initial = 'Rworkflow::SidekiqFlowTest::PostcardSend'
      end

      initial_objects = (0...20).to_a
      workflow = SidekiqFlow.create(lifecycle, 'CollectorWorkflow', {})
      workflow.start(initial_objects)

      assert workflow.finished?, 'Rworkflow finish successfully'
      assert_equal 20, RedisRds::String.new('Rworkflow::SidekiqFlowTest::PostcardSend').get.to_i, 'All initial objects should be processed by the first state one by one'
      assert_equal 1, RedisRds::String.new('Rworkflow::SidekiqFlowTest::PostcardSend_card').get.to_i, 'All initial objects should be processed by the first state one by one'
      assert_equal 1, RedisRds::String.new('Rworkflow::SidekiqFlowTest::PostcardCollector').get.to_i, 'All initial objects should be processed by the collector state all at once'
      assert_equal initial_objects.size, RedisRds::String.new('Rworkflow::SidekiqFlowTest::PostcardCollector_card').get.to_i, 'All initial objects should be processed by the collector state all at once'
    end

    def test_gated
      lifecycle = Lifecycle.new do |lc|
        lc.state('Rworkflow::SidekiqFlowTest::Floating', cardinality: 10) do |state|
          state.transition :rescued, 'Rworkflow::SidekiqFlowTest::Lifeboat'
          state.transition :drowned, Rworkflow::Flow::STATE_FAILED
        end
        lc.state('Rworkflow::SidekiqFlowTest::Lifeboat', cardinality: 2, policy: SidekiqFlow::STATE_POLICY_GATED) do |state|
          state.transition :landed, Rworkflow::Flow::STATE_SUCCESSFUL
          state.transition :starved, Rworkflow::Flow::STATE_FAILED
        end

        lc.initial = 'Rworkflow::SidekiqFlowTest::Floating'
      end

      initial_objects = (0...20).to_a
      workflow = SidekiqFlow.create(lifecycle, 'Lethal Workflow 4: Lethalerest', {})

      workflow.start(initial_objects)
      assert !workflow.finished?
      workflow.open_gate('Rworkflow::SidekiqFlowTest::Lifeboat')
      assert workflow.finished?

      counters = workflow.get_counters
      assert_equal 18, counters[Rworkflow::Flow::STATE_FAILED]
      assert_equal 2, counters[Rworkflow::Flow::STATE_SUCCESSFUL]

      assert 2, RedisRds::String.new('Rworkflow::SidekiqFlowTest::Floating').get.to_i
      assert 6, RedisRds::String.new('Rworkflow::SidekiqFlowTest::Lifeboat').get.to_i
    end

    class Floating < Worker
      def process(objects)
        rescued, drowned = objects.partition(&:even?)
        transition(:rescued, rescued)
        transition(:drowned, drowned)
        RedisRds::String.new(self.class.name).incr
      end
    end

    class Lifeboat < Worker
      def process(objects)
        landed, starved = objects.partition { |object| object < 4 }
        transition(:landed, landed)
        transition(:starved, starved)
        RedisRds::String.new(self.class.name).incr
      end
    end

    class Land < Worker
      def process(objects)
        rescued, died = objects.partition { |object| object == 0 }
        transition(:rescued, rescued)
        transition(:died, died)
        RedisRds::String.new(self.class.name).incr
      end
    end

    class PostcardSend < Worker
      def process(objects)
        transition(:sent, objects)
        RedisRds::String.new(self.class.name).incr
        RedisRds::String.new("#{self.class.name}_card").set(objects.size)
      end
    end

    class PostcardCollector < Worker
      def process(objects)
        transition(:received, objects)
        RedisRds::String.new(self.class.name).incr
        RedisRds::String.new("#{self.class.name}_card").set(objects.size)
      end
    end
  end
end
