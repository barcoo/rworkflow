module Rworkflow
  class SidekiqState
    attr_accessor :worker_class

    def initialize(worker_class, *args)
      super(*args)
      @worker_class = worker_class
    end
  end
end
