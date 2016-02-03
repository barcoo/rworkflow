require 'rworkflow/minitest/worker'
require 'rworkflow/minitest/test'

if defined?(Minitest)
  class Minitest::Test
    include Rworkflow::Minitest::Test
  end
end
