module Rworkflow
  class SidekiqLifecycle < Lifecycle
    def state(name, options = {}, &block)
      options = DEFAULT_STATE_OPTIONS.merge(options)
      options[:worker] = name if options[:worker].blank?

      new_state = SidekiqState.new(options[:worker], options[:cardinality], options[:priority], options[:policy])
      yield(new_state) if block_given?

      @states[name] = new_state
    end
  end
end
