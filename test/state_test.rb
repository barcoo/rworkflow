require 'test_helper'

module Rworkflow
  class StateTest < ActiveSupport::TestCase
    def setup
      super
      @state = State.new
      RedisRds::Object.flushdb
    end

    def teardown
      super
    end

    def test_transition
      @state.transition('a', 'b')
      @state.transition('b', 'c')

      assert_equal 'b', @state.transitions['a'], 'Transition A->B missing.'
      assert_equal 'c', @state.transitions['b'], 'Transition B->C missing.'
    end

    def test_perform
      @state.transition('a', 'b')
      @state.transition('b', 'c')

      assert_equal 'b', @state.perform('a'), 'Transition A->B missing.'
      assert_equal 'c', @state.perform('b'), 'Transition B->C missing.'
    end

    def test_equality
      other_state = State.new

      assert_equal @state, other_state, 'State A and B should be equal.'

      other_state.policy = State::STATE_POLICY_WAIT
      assert_not_equal @state, other_state, 'State A != B: different policies!'

      other_state = State.new
      other_state.cardinality = 32
      assert_not_equal @state, other_state, 'State A != B: different cardinalities!'

      other_state = State.new
      other_state.transition('a', 'b')
      other_state.transition('b', 'c')
      @state.transition('a', 'b')
      @state.transition('b', 'c')
      assert_equal @state, other_state, 'State A === B: same transitions!'

      other_state.transition('c', 'd')
      assert_not_equal @state, other_state, 'State A != B: different transitions!'
    end

    def test_serialization
      other_state = State.new
      other_state.transition('a', 'b')
      other_state.transition('b', 'c')
      assert_not_equal @state.serialize, other_state.serialize, 'State A should not equal B: serialization failed'

      @state.transition('a', 'b')
      @state.transition('b', 'c')
      assert_equal @state.serialize, other_state.serialize, 'State A should equal B: serialization failed'
    end

    def test_clone
      cloned = @state.clone
      assert_equal @state, cloned, 'Original and cloned states should be equal'
      assert !@state.equal?(cloned), 'Original and cloned states should not be the same object'

      @state.transition('a', 'b')
      @state.policy = State::STATE_POLICY_WAIT
      @state.cardinality = 2
      cloned = @state.clone
      assert_equal @state, cloned, 'Original and cloned states should be equal'
      assert !@state.equal?(cloned), 'Original and cloned states should not be the same object'
    end

    def test_merge
      other_state = State.new(cardinality: 2, policy: State::STATE_POLICY_WAIT)
      merged = @state.merge(other_state)
      assert_equal merged, other_state, 'Merged state should be equal to state B'

      other_state.transition('a', 'b')
      other_state.transition('b', 'c')
      @state.transition('a', 'c')
      @state.transition('c', 'd')

      expected_state = other_state.clone
      expected_state.transition('c', 'd')
      merged = @state.merge(other_state)
      assert_equal merged, expected_state, 'Merged state should have same properties as B plus additional transition C->D'
    end
  end
end
