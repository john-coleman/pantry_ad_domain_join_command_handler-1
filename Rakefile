#!/usr/bin/env rake
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

desc 'Run RuboCop'
RuboCop::RakeTask.new(:rubocop) do |task|
  # don't abort rake on failure
  task.fail_on_error = true
end

task default: :rubocop

RSpec::Core::RakeTask.new(:spec)

task :default => :spec