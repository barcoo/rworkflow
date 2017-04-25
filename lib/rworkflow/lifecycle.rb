module Rworkflow
  class Lifecycle
    attr_reader :states
    attr_accessor :initial, :default, :state_class, :state_options

    CARDINALITY_ALL_STARTED = :all_started # Indicates a cardinality equal to the jobs pushed at the start of the workflow

    RESERVED_STATE_NAMES = [Rworkflow::Flow::STATE_FAILED, Rworkflow::Flow::STATE_SUCCESSFUL].map(&:to_s).freeze
    DEFAULT_CARDINALITY = State::DEFAULT_CARDINALITY
    STATE_POLICY_NO_WAIT = State::STATE_POLICY_NO_WAIT
    DEFAULT_STATE_OPTIONS = {
      cardinality: self::DEFAULT_CARDINALITY,
      policy: self::STATE_POLICY_NO_WAIT
    }.freeze

    def initialize(state_class: State, state_options: {})
      @state_options = DEFAULT_STATE_OPTIONS.merge(state_options)
      @state_class = state_class
      @states = {}.with_indifferent_access
      @default = nil
      yield(self) if block_given?
    end

    def state(name, options = {})
      options = @state_options.merge(options)
      new_state = @state_class.new(**options)

      raise ArgumentError, 'given state name is a reserved state name' if RESERVED_STATE_NAMES.include?(name.to_s)
      raise ArgumentError, 'no two states can have the same name in a lifecycle' if @states.key?(name)

      yield(new_state) if block_given?

      @states[name] = new_state
    end

    def transition(from, name)
      from_state = @states[from]
      raise(StateError, from) if from_state.nil?

      return from_state.perform(name, @default)
    end

    def concat!(from, name, lifecycle, &state_merge_handler)
      state_merge_handler ||= lambda do |_, original_state, concat_state|
        original_state.merge(concat_state)
      end

      @states.merge!(lifecycle.states, &state_merge_handler)

      next_state = lifecycle.initial
      @states[from].transition(name, next_state)
      return self
    end

    def rename_state(old_state_name, new_state_name)
      old_state = @states[old_state_name]
      @states[new_state_name] = old_state
      @states.delete(old_state)

      @initial = new_state_name if @initial == old_state_name
    end

    def to_h
      return {
        initial: @initial,
        default: @default,
        state_class: @state_class,
        state_options: @state_options,
        states: Hash[@states.map { |name, state| [name, state.to_h] }]
      }
    end

    def to_graph
      states = @states || []
      return digraph do
        states.each do |from, state|
          state.transitions.each do |transition, to|
            edge(from.to_s, to.to_s).label(transition.to_s)
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
          lf.initial = hash[:initial]
          lf.default = hash[:default]
          lf.state_options = hash[:state_options]
          lf.state_class = hash[:state_class]

          hash[:states].each do |name, state_hash|
            lf.states[name] = lf.state_class.unserialize(state_hash)
          end
        end
      end
    end
  end
end
