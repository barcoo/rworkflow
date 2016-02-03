module Rworkflow
  # Disable pushing back indefinitely
  class Worker
    def initialize(*args)
      super
      @__test_results = Hash.new { |hash, key| hash[key] = [] }
    end

    def transition(to_state, objects)
      @__test_results[to_state].concat(objects)
    end

    def push_back(objects)
      @__test_results[@state_name || self.class.name].concat(objects)
    end
  end
end
