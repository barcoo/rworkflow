require 'sidekiq'

module Rworkflow
  class Worker
    include Sidekiq::Worker
    include SidekiqHelper

    REPORT_MISSING_FLOW = 'MISSING_FLOW'

    sidekiq_options queue: :mysql2

    def perform(id)
      @workflow = self.class.load_workflow(id)
      if @workflow.present?
        if !@workflow.paused?
          @workflow.fetch(self.jid, self.class.name) do |objects|
            process(objects) if objects.present?
          end
        end
      end
    rescue Exception => e
      #"Exception produced on #{self.class.name} for flow #{id} on perform: #{e.message}\n#{e.backtrace}")
      raise e
    end

    def transition(to_state, objects)
      @workflow.transition(self.class.name, to_state, objects)
    end

    def push_back(objects)
      @workflow.push(objects, self.class.name)
    end

    def process(objects)
      raise NotImplementedError
    end

    class << self
      def generate_lifecycle(&block)
        return Rworkflow::Lifecycle.new do |lc|
          lc.state(self.class.name, &block)
          lc.initial = self.class.name
        end
      end

      def load_workflow(id)
        workflow = Flow.load(id)
        if workflow.present? && workflow.valid?
          return workflow
        end

        #report(REPORT_MISSING_FLOW, "Worker #{self.name} tried to load non existent workflow #{id}")
        return nil
      end
    end
  end
end
