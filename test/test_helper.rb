# Configure Rails Environment
ENV['RAILS_ENV'] = 'test'

require File.expand_path('../dummy/config/environment.rb', __FILE__)
require 'rails/test_help'

Rails.backtrace_cleaner.remove_silencers!

connection = Redis.new(
  host: 'localhost',
  db: 1,
  port: 6379,
  timeout: 30,
  thread_safe: true
)

RedisRds.configure(
  connection: connection,
  namespace: 'testns'
)

# Load support files
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }
