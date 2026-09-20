require 'rubygems'
require 'bundler'
require 'rspec/core/rake_task'
require 'dotenv'
Dotenv.load('.env.test')

RSpec::Core::RakeTask.new(:spec)

task default: :spec
