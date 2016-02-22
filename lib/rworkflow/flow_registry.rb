module Rworkflow
  class FlowRegistry
    REDIS_PREFIX = 'flow:__registry'.freeze

    def initialize(prefix = nil)
      @redis_key = [REDIS_PREFIX, prefix].compact.join(':')
      @public = RedisRds::SortedSet.new("#{@redis_key}:public")
      @private = RedisRds::SortedSet.new("#{@redis_key}:private")
    end

    # Warning: using parent_class forces us to load everything, make this potentially much slower as we have to do the
    # pagination in the app, not in the db
    def all(parent_class: nil, **options)
      # load every ID if we have a parent_class
      options.merge(from: nil, to: nil) unless parent_class.nil?

      ids = self.public_flows(options) + self.private_flows(options)
      unless parent_class.nil?
        from = from.to_i
        to = to.nil? ? -1 : to.to_i

        ids.select! do |id|
          klass = Flow.read_flow_class(id)
          !klass.nil? && klass <= parent_class
        end.slice!(from..to)
      end

      return ids
    end

    def public_flows(options = {})
      return get(@public, **options)
    end

    def private_flows(options = {})
      return get(@private, **options)
    end

    def add(flow)
      key = flow.created_at.to_i

      if flow.public?
        @public.add(key, flow.id)
      else
        @private.add(key, flow.id)
      end
    end

    def remove(flow)
      if flow.public?
        @public.remove(flow.id)
      else
        @private.remove(flow.id)
      end
    end

    def include?(flow)
      if flow.public?
        @public.include?(flow.id)
      else
        @private.include?(flow.id)
      end
    end

    def get(zset, from: nil, to: nil, order: :asc)
      from = from.to_i
      to = to.nil? ? -1 : to.to_i

      zset.range(from, to, order: order)
    end
    private :get
  end
end
