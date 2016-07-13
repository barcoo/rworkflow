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
            process(objects) if objects.present?
          end
        end
      end
    rescue Exception => e
      Rails.logger.error("Exception produced on #{@state_name} for flow #{id} on perform: #{e.message}\n#{e.backtrace}")
      raise e
    end

    def transition(to_state, objects)
      @workflow.transition(@state_name, to_state, objects)
    end

    def push_back(objects)
      @workflow.push(objects, @state_name)
    end

    def process(objects)
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
        if !workflow.nil? && workflow.valid?
          return workflow
        end

        Rails.logger.warn("Worker #{self.name} tried to load non existent workflow #{id}")
        return nil
      end
    end
  end
end
