module Rworkflow
  class SidekiqLifecycle < Lifecycle
    def initialize(**options)
      options[:state_class] ||= SidekiqState
      super(**options)
    end
  end
end
