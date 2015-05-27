module Rworkflow
  class State
    DEFAULT_CARDINALITY = 1
    DEFAULT_PRIORITY = nil

    # To be refactored into Policy objects
    STATE_POLICY_WAIT = :wait
    STATE_POLICY_NO_WAIT = :no_wait

    attr_accessor :cardinality, :priority, :policy
    attr_reader :transitions

    def initialize(cardinality = DEFAULT_CARDINALITY, priority = DEFAULT_PRIORITY, policy = STATE_POLICY_NO_WAIT)
      @cardinality = cardinality
      @priority = priority
      @policy = policy

      @transitions = {}
    end

    def transition(name, to)
      @transitions[name] = to
    end

    def perform(name, default=nil)
      to_state = @transitions[name] || default
      raise TransitionError.new(name) if to_state.nil?
      return to_state
    end

    # Default rule: new state overwrites old state when applicable
    def merge!(state)
      @cardinality = state.cardinality
      @priority = state.priority
      @policy = state.policy

      @transitions.merge!(state.transitions) do |name, _, transition|
        transition
      end

      return self
    end

    def merge(state)
      return self.clone.merge!(state)
    end

    def clone
      cloned = State.new(@cardinality, @priority, @policy)
      @transitions.each { |from, to| cloned.transition(from, to) }
      return cloned
    end

    def ==(state)
      return @cardinality == state.cardinality &&
        @priority == state.priority &&
        @policy == state.policy &&
        @transitions == state.transitions
    end

    def to_h
      return {
        transitions: @transitions,
        cardinality: @cardinality,
        priority: @priority,
        policy: @policy
      }
    end

    def to_graph
      transitions = @transitions # need to capture for block, as digraph rebinds context

      return digraph do
        transitions.each do |transition, to|
          edge('self', to).label(transition.to_s)
        end
      end
    end

    def inspect
      return "[ Cardinality: #{@cardinality} ; Policy: #{@policy} ; Priority: #{@priority} ] -> #{to_graph.to_s}"
    end

    def serialize
      return self.class.serialize(self)
    end

    class << self
      def serialize(state)
        return state.to_h
      end

      def unserialize(state_hash)
        state = self.new(state_hash[:cardinality], state_hash.fetch(:priority, DEFAULT_PRIORITY), state_hash.fetch(:policy, STATE_POLICY_NO_WAIT))

        state_hash[:transitions].each do |from, to|
          state.transition from, to
        end

        return state
      end
    end
  end
end
