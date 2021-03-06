require 'rworkflow/state_error'

module Rworkflow
  class TransitionError < StateError
    def message
      return "#{@name} transition does not exist"
    end
  end
end
