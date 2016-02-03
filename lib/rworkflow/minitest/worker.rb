module Rworkflow
  # Disable pushing back indefinitely
  class Worker
    def initialize(*args)
      super
      @__pushed_back = []
    end

    def pushed_back
      return @__pushed_back
    end

    def push_back(objects)
      @__pushed_back.concat(objects)
    end
  end
end
