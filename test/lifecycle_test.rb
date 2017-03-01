require 'test_helper'

module Rworkflow
  class LifecycleTest < ActiveSupport::TestCase
    def setup
      super
      RedisRds::Object.flushdb
    end

    def test_definition
      lifecycle = Lifecycle.new do |lc|
        lc.state("State1") do |state|
          state.transition :pushed, :successful
        end

        lc.initial = 'State1'
      end

      assert_equal 'State1', lifecycle.initial
      assert_equal :successful, lifecycle.transition("State1", :pushed)
      assert_raises(Rworkflow::StateError) { lifecycle.transition("UnexistingState", :pushed) }
      assert_raises(Rworkflow::TransitionError) { lifecycle.transition("State1", :non_existing_transition) }

      lifecycle.default = Rworkflow::Flow::STATE_FAILED
      assert_equal Rworkflow::Flow::STATE_FAILED, lifecycle.default
      assert_equal Rworkflow::Flow::STATE_FAILED, lifecycle.transition("State1", :non_existing_transition)
    end

    def test_serialization
      lifecycle = Lifecycle.new do |lc|
        lc.state("State1") do |state|
          state.transition :pushed, :successful
        end

        lc.initial = "State1"
      end

      serialized = lifecycle.serialize

      unserialized = Lifecycle.unserialize(serialized)

      assert_equal lifecycle.initial, unserialized.initial
      assert_equal  Set.new(lifecycle.states.keys), Set.new(unserialized.states.keys)
      assert lifecycle.states.all? {|name, state| unserialized.states[name].instance_eval{@transitions} == state.instance_eval{@transitions} }
    end

    def test_concat
      lifecycle_one = LCFactory.simple_lifecycle("1", :next)
      lifecycle_two = LCFactory.simple_lifecycle("2", :finish)

      lifecycle_one.concat!("1", :next, lifecycle_two)

      assert_equal '1', lifecycle_one.initial
      assert_equal '2', lifecycle_one.transition("1", :next)
      assert_equal SidekiqFlow::STATE_SUCCESSFUL, lifecycle_one.transition("2", :finish)

      lifecycle_three = LCFactory.simple_lifecycle("3", :finish)
      lifecycle_three.state('1') do |s|
        s.transition(:next, '3')
        s.transition(:prev, '2')
      end

      lifecycle_one.concat!('2', :finish, lifecycle_three)
      assert_equal '3', lifecycle_one.transition('1', :next)
      assert_equal '2', lifecycle_one.transition('1', :prev)
      assert_equal '3', lifecycle_one.transition('2', :finish)
    end

    class LCFactory
      def self.simple_lifecycle(state_name, transition, cardinality = 1)
        return Rworkflow::Lifecycle.new do |cycle|
          cycle.state(state_name, cardinality: cardinality) do |state|
            state.transition transition, Rworkflow::SidekiqFlow::STATE_SUCCESSFUL
            state.transition :failed, Rworkflow::SidekiqFlow::STATE_FAILED
          end
          cycle.initial = state_name
        end
      end
    end
  end
end
