module Rworkflow
  class State
    DEFAULT_CARDINALITY = 1

    # To be refactored into Policy objects
    STATE_POLICY_WAIT = :wait
    STATE_POLICY_NO_WAIT = :no_wait

    attr_accessor :cardinality, :policy
    attr_reader :transitions

    def initialize(cardinality: DEFAULT_CARDINALITY, policy: STATE_POLICY_NO_WAIT, **_)
      @cardinality = cardinality
      @policy = policy
      @transitions = {}
    end

    def transition(name, to)
      @transitions[name] = to
    end

    def perform(name, default = nil)
      to_state = @transitions[name] || default
      raise(TransitionError, name) if to_state.nil?
      return to_state
    end

    # Default rule: new state overwrites old state when applicable
    def merge!(state)
      @cardinality = state.cardinality
      @policy = state.policy

      @transitions.merge!(state.transitions) do |_, _, transition|
        transition
      end

      return self
    end

    def merge(state)
      return self.clone.merge!(state)
    end

    def clone
      cloned = self.class.new(cardinality: @cardinality, policy: @policy)
      @transitions.each { |from, to| cloned.transition(from, to) }
      return cloned
    end

    def ==(other)
      return @cardinality == other.cardinality && @policy == other.policy && @transitions == other.transitions
    end

    def to_h
      return {
        transitions: @transitions,
        cardinality: @cardinality,
        policy: @policy
      }
    end

    def to_graph
      transitions = @transitions # need to capture for block, as digraph rebinds context

      return digraph do
        transitions.each do |transition, to|
          edge('self', to.to_s).label(transition.to_s)
        end
      end
    end

    def inspect
      return "[ Cardinality: #{@cardinality} ; Policy: #{@policy} ] -> #{to_graph}"
    end

    def serialize
      return self.class.serialize(self)
    end

    class << self
      def serialize(state)
        return state.to_h
      end

      def unserialize(state_hash)
        state = self.new(**state_hash)

        state_hash[:transitions].each do |from, to|
          state.transition(from, to)
        end

        return state
      end
    end
  end
end
