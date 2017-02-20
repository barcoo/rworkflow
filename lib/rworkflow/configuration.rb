module Rworkflow
  class Configuration
    # @return [Bool] whether sidekiq jobs should be asynchronous
    attr_accessor :sidekiq_perform_async

    def initialize
      @sidekiq_perform_async = true
    end
  end
end
