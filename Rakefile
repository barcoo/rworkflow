begin
  require 'bundler/setup'
rescue LoadError
  puts 'You must `gem install bundler` and `bundle install` to run rake tasks'
end

require 'rdoc/task'

RDoc::Task.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title    = 'Rworkflow'
  rdoc.options << '--line-numbers'
  rdoc.rdoc_files.include('README.rdoc')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

Bundler::GemHelper.install_tasks

require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = false
end

task default: :test

namespace :cim do
  desc 'Tags, updates README, and CHANGELOG and pushes to Github. Requires ruby-git'
  task :release do
    tasks = ['cim:assert_clean_repo', 'cim:git_fetch', 'cim:set_new_version', 'cim:update_readme', 'cim:update_changelog', 'cim:commit_changes', 'cim:tag']
    begin
      tasks.each { |task| Rake::Task[task].invoke }
      `git push && git push origin '#{Rworkflow::VERSION}'`
    rescue => error
      puts ">>> ERROR: #{error}; might want to reset your repository"
    end
  end

  desc 'Fails if the current repository is not clean'
  task :assert_clean_repo do
    status = `git status -s`.chomp.strip
    if status.strip.empty?
      status = `git log origin/master..HEAD`.chomp.strip # check if we have unpushed commits
      if status.strip.empty?
        puts '>>> Repository is clean!'
      else
        puts '>>> Please push your committed changes before releasing!'
        exit(-1)
      end
    else
      puts '>>> Please stash or commit your changes before releasing!'
      exit(-1)
    end
  end

  desc 'Fetches latest tags/commits'
  task :git_fetch do
    puts '>>> Fetching latest git refs'
    `git fetch --tags`
  end

  desc 'Requests the new version number'
  task :set_new_version do
    STDOUT.print(">>> New version number (current: #{Rworkflow::VERSION}; leave blank if already updated): ")
    input = STDIN.gets.strip.tr("'", "\'")

    current = if input.empty?
      Rworkflow::VERSION
    else
      unless input =~ /[0-9]+\.[0-9]+\.[0-9]+/
        puts '>>> Please use semantic versioning!'
        exit(-1)
      end

      input
    end

    latest = `git describe --abbrev=0`.chomp.strip
    unless Gem::Version.new(current) > Gem::Version.new(latest)
      puts ">>> Latest tagged version is #{latest}; make sure gem version (#{current}) is greater!"
      exit(-1)
    end

    if !input.empty?
      `sed -i -u "s@VERSION = '#{Rworkflow::VERSION}'@VERSION = '#{input}'@" #{File.expand_path('../lib/rworkflow/version.rb', __FILE__)}`
      $VERBOSE = nil
      Rworkflow.const_set('VERSION', input)
      $VERBOSE = false

      `bundle check` # force updating version
    end
  end

  desc 'Updates README with latest version'
  task :update_readme do
    puts '>>> Updating README.md'
    replace = %([![GitHub release](https://img.shields.io/badge/release-#{Rworkflow::VERSION}-blue.png)](https://github.com/barcoo/rworkflow/releases/tag/#{Rworkflow::VERSION}))

    `sed -i -u 's@^\\[\\!\\[GitHub release\\].*$@#{replace}@' README.md`
  end

  desc 'Updates CHANGELOG with commit log from last tag to this one'
  task :update_changelog do
    puts '>>> Updating CHANGELOG.md'
    latest = `git describe --abbrev=0`.chomp.strip
    log = `git log --pretty=format:'- [%h](https://github.com/barcoo/rworkflow/commit/%h) *%ad* __%s__ (%an)' --date=short '#{latest}'..HEAD`.chomp

    changelog = File.open('.CHANGELOG.md', 'w')
    changelog.write("# Changelog\n\n###{Rworkflow::VERSION}\n\n#{log}\n\n")
    File.open('CHANGELOG.md', 'r') do |file|
      begin
        file.readline # skip first two lines
        file.readline
        while buffer = file.read(2048)
          changelog.write(buffer)
        end
      rescue => error
      end
    end

    changelog.close
    `mv '.CHANGELOG.md' 'CHANGELOG.md'`
  end

  desc 'Commits the README/CHANGELOG changes'
  task :commit_changes do
    puts '>>> Committing updates to README/CHANGELOG'
    `git commit -am'Updated README.md and CHANGELOG.md on new release'`
  end

  desc 'Creates and pushes the tag to git'
  task :tag do
    puts '>>> Tagging'
    STDOUT.print('>>> Please enter a tag message: ')
    input = STDIN.gets.strip.tr("'", "\'")
    `git tag -a '#{Rworkflow::VERSION}' -m '#{input}'`
  end
end
