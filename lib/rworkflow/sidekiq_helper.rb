require 'sidekiq/api'

module Rworkflow
  module SidekiqHelper
    def self.included(klass)
      klass.send :extend, ClassMethods
    end

    module ClassMethods
      # Mix-in methods
      def enqueue_job(*params)
        if should_perform_job_async?
          self.perform_async(*params)
        else
          inline_perform(params)
        end
      end

      def should_perform_job_async?
        return Rworkflow.config.sidekiq_perform_async
      end

      def inline_perform(params)
        worker = self.new
        args = JSON.parse(params.to_json)
        jid = Digest::MD5.hexdigest((Time.now.to_f * 1000).to_i.to_s)
        worker.jid = jid
        worker.perform(*args)
      end
    end

    # Static methods
    class << self
      def configure_server(host, port, db)
        Sidekiq.configure_server do |config|
          config.redis = { url: "redis://#{host}:#{port}/#{db}", namespace: 'sidekiq' }
          config.server_middleware do |chain|
            chain.add SidekiqServerMiddleware
          end
        end
      end

      def configure_client(host, port, db)
        Sidekiq.configure_client do |config|
          config.redis = { url: "redis://#{host}:#{port}/#{db}", namespace: 'sidekiq' }
        end
      end

      def queue_sizes
        stats = Sidekiq::Stats.new
        return stats.queues
      end
    end
  end
end
