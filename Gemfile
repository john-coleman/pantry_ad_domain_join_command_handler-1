source 'https://rubygems.org'

gem 'daemons'
gem 'pantry_daemon_common', git: 'git@github.com:wongatech/pantry_daemon_common.git', :tag => 'v0.2.4'
gem 'winrm', '~> 1.1.2'

group :development do
  gem 'guard-rspec'
  gem 'guard-bundler'
end

group :test, :development do
  gem 'simplecov', require: false
  gem 'simplecov-rcov', require: false
  gem 'rspec-fire'
  gem 'rspec'
  gem 'pry-debugger'
  gem 'rake'
end
