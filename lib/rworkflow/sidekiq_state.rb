module Rworkflow
  class SidekiqState < State
    attr_accessor :worker_class

    def initialize(worker: nil, **options)
      super(**options)
      @worker_class = worker
    end

    def merge!(state)
      super
      @worker_class = state.worker_class if state.respond_to?(:worker_class)
    end

    def clone
      cloned = super
      cloned.worker_class = @worker_class

      return cloned
    end

    def ==(state)
      return super && state.worker_class == @worker_class
    end

    def to_h
      h = super
      h[:worker_class] = @worker_class

      return h
    end

    class << self
      def unserialize(state_hash)
        state = super(state_hash)
        state.worker_class = state_hash[:worker_class]

        return state
      end
    end
  end
end
