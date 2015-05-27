module Rworkflow
  class StateError < StandardError
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def message
      return "#{@name} state does not exist"
    end
  end
end
