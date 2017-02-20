require 'redis_rds'

require 'rworkflow/version'
require 'rworkflow/sidekiq_helper'
require 'rworkflow/flow_registry'
require 'rworkflow/flow'
require 'rworkflow/state'
require 'rworkflow/state_error'
require 'rworkflow/lifecycle'
require 'rworkflow/sidekiq_flow'
require 'rworkflow/sidekiq_lifecycle'
require 'rworkflow/sidekiq_state'
require 'rworkflow/transition_error'
require 'rworkflow/worker'

module Rworkflow
  class << self
    def config
      return @config ||= Rworkflow::Configuration.new
    end

    def configure
      yield(config) if block_given?
      return config
    end
  end
end
