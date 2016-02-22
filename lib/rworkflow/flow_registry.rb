module Rworkflow
  class FlowRegistry
    REDIS_PREFIX = 'flow:__registry'.freeze

    def initialize(prefix = nil)
      @redis_key = [REDIS_PREFIX, prefix].compact.join(':')
      @public = RedisRds::SortedSet.new("#{@redis_key}:public")
      @private = RedisRds::SortedSet.new("#{@redis_key}:private")
    end

    def all(options = {})
      return self.public_flows(options) + self.private_flows(options)
    end

    def public_flows(options = {})
      return get(@public, options)
    end

    def private_flows(options = {})
      return get(@private, options)
    end

    def add(flow)
      key = flow.created_at.to_i

      if flow.public?
        @public.add(key, flow)
      else
        @private.add(key, flow)
      end
    end

    def remove(flow)
      if flow.public?
        @public.remove(flow)
      else
        @private.remove(flow)
      end
    end

    def include?(flow)
      if flow.public?
        @public.include?(flow)
      else
        @private.include?(flow)
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
