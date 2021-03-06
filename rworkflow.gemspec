$LOAD_PATH.push File.expand_path('../lib', __FILE__)

require 'rworkflow/version'

Gem::Specification.new do |s|
  s.name = 'rworkflow'
  s.version = Rworkflow::VERSION
  s.required_ruby_version = '>= 2'
  s.authors = ['barcoo']
  s.email = ['roots@checkitmobile.com']
  s.homepage = 'https://github.com/barcoo/rworkflow'
  s.summary = 'rworkflow - workflow framework for Ruby'
  s.description = 'rworkflow - workflow framework for Ruby'
  s.license = 'MIT'

  s.files = Dir['{app,config,db,lib}/**/*', 'MIT-LICENSE', 'Rakefile', 'README.md']
  s.test_files = Dir['test/**/*']

  s.add_dependency 'sidekiq', '~> 4'
  s.add_dependency 'rails', '~> 5.0'
  s.add_dependency 'redis_rds', '~> 0.1'
  s.add_development_dependency 'sqlite3', '~> 1.3'
end
