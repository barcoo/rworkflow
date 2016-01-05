$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "rworkflow/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "rworkflow"
  s.version     = Rworkflow::VERSION
  s.authors     = ["barcoo"]
  s.email       = ["roots@checkitmobile.com"]
  s.homepage    = "http://www.barcoo.com"
  s.summary     = "TBC: Summary of Rworkflow."
  s.description = "TBC: Description of Rworkflow."
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["test/**/*"]

  s.add_dependency "sidekiq", "~> 3.4.2"
  s.add_dependency "rails", ">= 4.1.1"

  s.add_development_dependency "sqlite3"
end
