# Configure Rails Environment
ENV['RAILS_ENV'] = 'test'

require 'simplecov'
require 'coveralls'

SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
  SimpleCov::Formatter::HTMLFormatter,
  Coveralls::SimpleCov::Formatter
])
SimpleCov.start

require File.expand_path('../dummy/config/environment.rb', __FILE__)
require 'rails/test_help'

Rails.backtrace_cleaner.remove_silencers!

Rworkflow.config.sidekiq_perform_async = false

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
