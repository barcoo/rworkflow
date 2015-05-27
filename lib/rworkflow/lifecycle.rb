module Rworkflow
  class Lifecycle
    attr_reader :states
    attr_accessor :initial, :default

    CARDINALITY_ALL_STARTED = :all_started # Indicates a cardinality equal to the jobs pushed at the start of the workflow

    DEFAULT_STATE_OPTIONS = {
      cardinality: State::DEFAULT_CARDINALITY,
      priority: State::DEFAULT_PRIORITY,
      policy: State::STATE_POLICY_NO_WAIT
    }

    def initialize(&block)
      @states = {}
      yield(self) if block_given?
    end

    def state(name, options = {}, &block)
      options = DEFAULT_STATE_OPTIONS.merge(options)

      new_state = State.new(options[:cardinality], options[:priority], options[:policy])
      yield(new_state) if block_given?

      @states[name] = new_state
    end

    def transition(from, name)
      from_state = @states[from]
      raise StateError.new(from) if from_state.nil?

      return from_state.perform(name, self.default)
    end

    def concat!(from, name, lifecycle, &state_merge_handler)
      state_merge_handler ||= -> (name, original_state, concat_state) do
        original_state.merge(concat_state)
      end

      @states.merge!(lifecycle.states, &state_merge_handler)

      next_state = lifecycle.initial
      @states[from].transition(name, next_state)
      return self
    end

    def to_h
      return {
        initial: @initial,
        default: @default,
        states: Hash[@states.map do |name, state|
          [name, state.to_h]
        end]
      }
    end

    def to_graph
      states = @states || []
      return digraph do
        states.each do |from, state|
          state.transitions.each do |transition, to|
            edge(from, to).label(transition.to_s)
          end
        end
      end
    end

    def serialize
      return self.class.serialize(self)
    end

    class << self
      def serialize(lifecycle)
        return lifecycle.to_h
      end

      def unserialize(hash)
        return self.new do |lf|
          hash[:states].each do |name, state_hash|
            lf.states[name] = State.unserialize(state_hash)
          end
          lf.initial = hash[:initial]
          lf.default = hash[:default]
        end
      end
    end
  end
end
