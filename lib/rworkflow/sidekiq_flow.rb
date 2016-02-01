module Rworkflow
  class SidekiqFlow < Flow

    STATE_POLICY_GATED = :gated
    MAX_EXPECTED_DURATION = 4.hours
    PRIORITIES = [:critical, :high, nil, :low]

    def initialize(id)
      super(id)
      @open_gates = RedisRds::Set.new("#{@redis_key}__open_gates")
    end

    def cleanup
      super()
      @open_gates.delete()
    end

    def push(objects, name)
      pushed = 0
      pushed = super(objects, name)
    ensure
      create_jobs(name, pushed) if pushed > 0
      return pushed
    end

    def expected_duration
      return MAX_EXPECTED_DURATION
    end

    def paused?
      return @flow_data.get(:paused).to_i > 0
    end

    def status
      return (paused?) ? 'Paused' : super()
    end

    def pause
      return if self.finished?
      @flow_data.incr(:paused)
    rescue StandardError => e
      Rails.logger.error("Error pausing flow #{self.id}: #{e.message}")
    end

    # for now assumes
    def continue
      return if self.finished? || !self.valid? || !self.paused?
      if @flow_data.decr(:paused) == 0
        workers = Hash[get_counters.select { |name, _| !self.class.terminal?(name) && name != :processing }]

        # enqueue jobs
        workers.each { |worker, num_objects| create_jobs(worker, num_objects) }
      end
    rescue StandardError => e
      Rails.logger.error("Error continuing flow #{self.id}: #{e.message}")
    end

    def create_jobs(state_name, num_objects)
      return if paused? || num_objects < 1 || self.class.terminal?(state_name) || gated?(state_name)
      state = @lifecycle.states[state_name]
      worker_class = begin
        state.worker_class.constantize
      rescue NameError => _
        Rails.logger.error("Trying to push to a non existent worker class #{state_name} in workflow #{@id}")
        nil
      end

      if worker_class.present?
        cardinality = get_state_cardinality(state_name)

        if state.policy == State::STATE_POLICY_WAIT
          amount = ((num_objects + get_state_list(state_name).size) / cardinality.to_f).floor
        else
          amount = (num_objects / cardinality.to_f).ceil
        end

        state_priority = self.priority || state.priority
        amount.times { worker_class.enqueue_job_with_priority(state_priority, @id, state_name) }
      end
    end

    def priority
      return @priority ||= begin self.get(:priority) end
    end

    def gated?(state_name)
      state = @lifecycle.states[state_name]
      return state.policy == STATE_POLICY_GATED && !@open_gates.include?(state_name)
    end

    def open_gate(state_name)
      @open_gates.add(state_name)
      num_objects = count(state_name)
      create_jobs(state_name, num_objects)
    end

    def close_gate(state_name)
      @open_gates.remove(state_name)
    end

    class << self
      def create(lifecycle, name = '', options)
        workflow = super(lifecycle, name, options)
        workflow.set(:priority, options[:priority]) unless options[:priority].nil?

        return workflow
      end

      def get_manual_priority
        return :high
      end

      def cleanup_broken_flows
        broken = []
        flows = self.all
        flows.each do |flow|
          if flow.valid?
            if flow.finished? && !flow.public?
              broken << [flow, 'finished']
            elsif !flow.started? && flow.created_at < 1.day.ago
              broken << [flow, 'never started']
            end
          else
            broken << [flow, 'invalid']
          end
        end

        broken.each do |flow_pair|
          flow_pair.first.cleanup
          puts "Cleaned up #{flow_pair.second} flow #{flow_pair.first.id}"
        end
        puts ">>> Cleaned up #{broken.size} broken flows <<<"
      end

      def enqueue_missing_jobs
        queued_flow_map = build_flow_map
        running_flows = self.all.select { |f| f.valid? && !f.finished? && !f.paused? }
        running_flows.each do |flow|
          state_map = queued_flow_map.fetch(flow.id, {})
          create_missing_jobs(flow, state_map)
        end
      end

      def build_flow_map
        flow_map = {}
        queues = SidekiqHelper.get_queue_sizes.keys
        queues.each do |queue_name|
          queue = Sidekiq::Queue.new(queue_name)
          queue.each do |job|
            klass = begin
              job.klass.constantize
            rescue NameError => _
              nil
            end

            if klass.present? && klass <= Rworkflow::Worker
              id = job.args.first
              state_name = jobs.args.second
              state_map = flow_map.fetch(id, {})
              state_map[state_name] = state_map.fetch(state_name, 0) + 1
              flow_map[id] = state_map
            end
          end
        end
        return flow_map
      end

      def create_missing_jobs(flow, state_map)
        counters = flow.get_counters
        counters.each do |state, num_objects|
          next if flow.class.terminal?(state) || state == :processing
          enqueued = state_map.fetch(state, 0) * flow.get_state_cardinality(state)
          missing = num_objects - enqueued
          if missing > 0
            flow.create_jobs(state, missing)
            puts "Created #{missing} missing jobs for state #{state} in flow #{flow.id}"
          end
        end
      end
    end
  end
end
