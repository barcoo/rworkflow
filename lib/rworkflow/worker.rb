require 'sidekiq'

module Rworkflow
  class Worker
    include Sidekiq::Worker
    include SidekiqHelper

    sidekiq_options queue: :mysql

    def perform(id, state_name)
      @workflow = self.class.load_workflow(id)
      @state_name = state_name
      if !@workflow.nil?
        if !@workflow.paused?
          @workflow.fetch(self.jid, state_name) do |objects|
            if objects.present?
              Rails.logger.debug("Starting #{self.class}::process() (flow #{id})")
              process(objects)
              Rails.logger.debug("Finished #{self.class}::process() (flow #{id})")
            else
              Rails.logger.debug("No objects to process for #{self.class}")
            end
          end
        end
      end
    rescue Exception => e
      Rails.logger.error("Exception produced on #{@state_name} for flow #{id} on perform: #{e.message}\n#{e.backtrace}")
      raise e
    end

    def transition(to_state, objects)
      @workflow.transition(@state_name, to_state, objects)
      Rails.logger.debug("State #{@state_name} transitioned #{objects.size} objects to state #{to_state} (flow #{@workflow.id})")
    end

    def push_back(objects)
      @workflow.push(objects, @state_name)
      Rails.logger.debug("State #{@state_name} pushed back #{objects.size} objects (flow #{@workflow.id})")
    end

    def process(_objects)
      raise NotImplementedError
    end

    class << self
      def generate_lifecycle(&block)
        return Rworkflow::Lifecycle.new do |lc|
          lc.state(self.class.name, worker: self.class, &block)
          lc.initial = self.class.name
        end
      end

      def load_workflow(id)
        workflow = Flow.load(id)
        return workflow if !workflow.nil? && workflow.valid?

        Rails.logger.warn("Worker #{self.name} tried to load non existent workflow #{id}")
        return nil
      end
    end
  end
end
