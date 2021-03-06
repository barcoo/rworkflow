module Rworkflow
  class Flow
    STATE_SUCCESSFUL = :successful
    STATE_FAILED = :failed
    STATES_TERMINAL = [STATE_FAILED, STATE_SUCCESSFUL].freeze
    STATES_FAILED = [STATE_FAILED].freeze

    REDIS_NS = 'flow'.freeze
    WORKFLOW_REGISTRY = "#{REDIS_NS}:__registry".freeze

    attr_accessor :id
    attr_reader :lifecycle

    def initialize(id)
      @id = id
      @redis_key = "#{REDIS_NS}:#{id}"

      @storage = RedisRds::Hash.new(@redis_key)
      @flow_data = RedisRds::Hash.new("#{@redis_key}__data")
      @processing = RedisRds::Hash.new("#{@redis_key}__processing")

      load_lifecycle
    end

    def load_lifecycle
      serialized = @storage.get(:lifecycle)
      unless serialized.nil?
        raw = self.class.serializer.load(serialized)
        @lifecycle = Rworkflow::Lifecycle.unserialize(raw) unless raw.nil?
      end
    rescue
      @lifecycle = nil
    end
    private :load_lifecycle

    def lifecycle=(new_lifecycle)
      @lifecycle = new_lifecycle
      @storage.set(:lifecycle, self.class.serializer.dump(@lifecycle.serialize))
    end

    def finished?
      return false unless started?
      total = self.counters.reduce(0) do |sum, pair|
        self.class.terminal?(pair[0]) ? sum : (sum + pair[1].to_i)
      end

      return total == 0
    end

    def status
      status = 'Running'
      status = successful? ? 'Finished' : 'Failed' if finished?

      return status
    end

    def created_at
      return @created_at ||= begin Time.zone.at(get(:created_at, 0)) end
    end

    def started?
      return !get(:start_time).nil?
    end

    def name
      return get(:name, @id)
    end

    def name=(name)
      return set(:name, name)
    end

    def start_time
      return Time.zone.at(get(:start_time, 0))
    end

    def finish_time
      return Time.zone.at(get(:finish_time, 0))
    end

    def expected_duration
      return Float::INFINITY
    end

    def valid?
      return !@lifecycle.nil?
    end

    def count(state)
      return get_list(state).size
    end

    def counters
      the_counters = @storage.get(:counters)
      if !the_counters.nil?
        the_counters = begin
          self.class.serializer.load(the_counters)
        rescue => e
          Rails.logger.error("Error loading stored flow counters: #{e.message}")
          nil
        end
      end
      return the_counters || counters!
    end

    # fetches counters atomically
    def counters!
      the_counters = { processing: 0 }

      names = @lifecycle.states.keys
      results = RedisRds::Object.connection.multi do
        self.class::STATES_TERMINAL.each { |name| get_list(name).size }
        names.each { |name| get_list(name).size }
        @processing.getall
      end

      (self.class::STATES_TERMINAL + names).each do |name|
        the_counters[name] = results.shift.to_i
      end

      the_counters[:processing] = results.shift.reduce(0) { |sum, pair| sum + pair.last.to_i }

      return the_counters
    end
    private :counters!

    def fetch(fetcher_id, state_name)
      @processing.set(fetcher_id, 1)
      list = get_state_list(state_name)
      unless list.nil?
        failed = []
        cardinality = @lifecycle.states[state_name].cardinality
        cardinality = get(:start_count).to_i if cardinality == Lifecycle::CARDINALITY_ALL_STARTED
        force_list_complete = @lifecycle.states[state_name].policy == State::STATE_POLICY_WAIT
        raw_objects = list.lpop(cardinality, force_list_complete)
        unless raw_objects.empty?
          objects = raw_objects.map do |raw_object|
            begin
              self.class.serializer.load(raw_object)
            rescue StandardError => _
              failed << raw_object
              nil
            end
          end.compact
          @processing.set(fetcher_id, objects.size)

          unless failed.empty?
            push(failed, STATE_FAILED)
            Rails.logger.error("Failed to parse #{failed.size} in workflow #{@id} for fetcher id #{fetcher_id} at state #{state_name}")
          end

          yield(objects) if block_given?
        end
      end
    ensure
      @processing.remove(fetcher_id)
      terminate if finished?
    end

    def list_objects(state_name, limit = -1)
      list = get_list(state_name)
      return list.get(0, limit).map { |object| self.class.serializer.load(object) }
    end

    def get_state_list(state_name)
      list = nil
      state = @lifecycle.states[state_name]

      if !state.nil?
        list = get_list(state_name)
      else
        Rails.logger.error("Tried accessing invalid state #{state_name} for workflow #{id}")
      end
      return list
    end
    private :get_state_list

    def terminate
      mutex = RedisRds::Mutex.new(self.id)
      mutex.synchronize do
        if !self.cleaned_up?
          set(:finish_time, Time.now.to_i)
          post_process

          if self.public?
            the_counters = counters!
            the_counters[:processing] = 0 # Some worker might have increased the processing flag at that time even if there is no more jobs to be done
            @storage.setnx(:counters, self.class.serializer.dump(the_counters))
            states_cleanup
          else
            self.cleanup
          end
        end
      end
    end

    def post_process; end
    protected :post_process

    def metadata_string
      return "Rworkflow: #{self.name}"
    end

    def cleaned_up?
      return states_list.all? { |name| !get_list(name).exists? }
    end

    def states_list
      states = self.class::STATES_TERMINAL
      states += @lifecycle.states.keys if valid?

      return states
    end

    def transition(from_state, name, objects)
      objects = Array.wrap(objects)
      to_state = begin
        lifecycle.transition(from_state, name)
      rescue Rworkflow::StateError => e
        Rails.logger.error("Error transitioning: #{e}")
        nil
      end

      if !to_state.nil?
        push(objects, to_state)
        log(from_state, name, objects.size)
      end
    end

    def logging?
      return get(:logging, false)
    end

    def log(from_state, transition, num_objects)
      logger.incrby("#{from_state}__#{transition}", num_objects.to_i) if logging?
    end

    def logger
      return @logger ||= begin
        RedisRds::Hash.new("#{@redis_key}__logger")
      end
    end

    def logs
      logs = {}
      if valid? && logging?
        state_transition_counters = logger.getall
        state_transition_counters.each do |state_transition, counter|
          state, transition = state_transition.split('__')
          logs[state] = {} unless logs.key?(state)
          logs[state][transition] = counter.to_i
        end
      end

      return logs
    end

    def get_state_cardinality(state_name)
      cardinality = @lifecycle.states[state_name].cardinality
      cardinality = self.get(:start_count).to_i if cardinality == Rworkflow::Lifecycle::CARDINALITY_ALL_STARTED
      return cardinality
    end

    def set(key, value)
      @flow_data.set(key, self.class.serializer.dump(value))
    end

    def get(key, default = nil)
      value = @flow_data.get(key)
      value = value.nil? ? default : self.class.serializer.load(value)

      return value
    end

    def incr(key, value = 1)
      return @flow_data.incrby(key, value)
    end

    def push(objects, state)
      objects = Array.wrap(objects)

      return 0 if objects.empty?

      list = get_list(state)
      list.rpush(objects.map { |object| self.class.serializer.dump(object) })

      return objects.size
    end
    private :push

    def get_list(name)
      return RedisRds::List.new("#{@redis_key}:lists:#{name}")
    end
    private :get_list

    def cleanup
      return if Rails.env.test?
      states_cleanup
      logger.delete
      @processing.delete
      self.class.unregister(self)
      @flow_data.delete
      @storage.delete
    end

    def states_cleanup
      return if Rails.env.test?
      states_list.each { |name| get_list(name).delete }
    end
    protected :states_cleanup

    def start(objects)
      objects = Array.wrap(objects)
      set(:start_time, Time.now.to_i)
      set(:start_count, objects.size)
      push(objects, lifecycle.initial)
      log(lifecycle.initial, 'initial', objects.size)
    end

    def total_objects_processed(counters = nil)
      return (counters || self.counters).reduce(0) do |sum, pair|
        if self.class.terminal?(pair[0])
          sum + pair[1]
        else
          sum
        end
      end
    end

    def total_objects(counters = nil)
      return (counters || self.counters).reduce(0) { |sum, pair| sum + pair[1] }
    end

    def total_objects_failed(counters = nil)
      return (counters || self.counters).reduce(0) do |sum, pair|
        if self.class.failure?(pair[0])
          sum + pair[1]
        else
          sum
        end
      end
    end

    def successful?
      return false if !finished?
      return !failed?
    end

    def failed?
      return false if !finished?
      return total_objects_failed > 0
    end

    def public?
      return @public ||= begin get(:public, false) end
    end

    class << self
      def create(lifecycle, name = '', options = {})
        id = generate_id(name)
        workflow = new(id)
        workflow.name = name
        workflow.lifecycle = lifecycle
        workflow.set(:created_at, Time.now.to_i)
        workflow.set(:public, options.fetch(:public, false))
        workflow.set(:logging, options.fetch(:logging, true))

        register(workflow)

        return workflow
      end

      def generate_id(workflow_name)
        now = Time.now.to_f
        random = Random.new(now)
        return "#{name}__#{workflow_name}__#{(Time.now.to_f * 1000).to_i}__#{random.rand(now).to_i}"
      end
      private :generate_id

      def cleanup(id)
        workflow = new(id)
        workflow.cleanup
      end

      def get_public_workflows(options = {})
        return registry.public_flows(options.reverse_merge(parent_class: self)).map { |id| load(id) }
      end

      def get_private_workflows(options = {})
        return registry.private_flows(options.reverse_merge(parent_class: self)).map { |id| load(id) }
      end

      def all(options = {})
        return registry.all(options.reverse_merge(parent_class: self)).map { |id| load(id) }
      end

      def load(id, klass = nil)
        workflow = nil

        klass = read_flow_class(id) if klass.nil?
        workflow = klass.new(id) if klass.respond_to?(:new)
        return workflow
      end

      def read_flow_class(id)
        klass = nil
        raw_class = id.split('__').first
        if !raw_class.nil?
          klass = begin
            raw_class.constantize
          rescue NameError => _
            Rails.logger.warn("Unknown flow class for workflow id #{id}")
            nil
          end
        end

        return klass
      end

      def registered?(workflow)
        return registry.include?(workflow)
      end

      def register(workflow)
        registry.add(workflow)
      end

      def unregister(workflow)
        registry.remove(workflow)
      end

      def terminal?(state)
        return self::STATES_TERMINAL.include?(state)
      end

      def failure?(state)
        return self::STATES_FAILED.include?(state)
      end

      def registry
        return @registry ||= begin
          FlowRegistry.new(Rworkflow::VERSION.to_s)
        end
      end

      def serializer
        YAML
      end
    end
  end
end
