module Rworkflow
  module Factory
    extend ActiveSupport::Concern

    module ClassMethods
      def simple_lifecycle(state_name, transition, cardinality = 1, priority=nil)
        return Rworkflow::Lifecycle.new do |cycle|
          cycle.state(state_name, {cardinality: cardinality, priority: priority}) do |state|
            state.transition transition, Rworkflow::SidekiqFlow::STATE_SUCCESSFUL
            state.transition :failed, Rworkflow::SidekiqFlow::STATE_FAILED
          end
          cycle.initial = state_name
        end
      end
    end
  end
end