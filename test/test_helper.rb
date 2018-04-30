File.expand_path("../../lib", __FILE__).tap do |lib|
  $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
end

require 'delayed/threaded'

gem_spec = Gem.loaded_specs['delayed_job'] if defined? Gem
puts "loaded gem 'delayed_job' '#{gem_spec.version.to_s}'" if gem_spec

gem 'test-unit' # uninitialized constant Test::Unit::TestResult::TestResultFailureSupport
require 'test/unit'
require 'test/unit/context'
begin; require 'mocha/setup'; rescue LoadError; require 'mocha'; end

TestImpl = Test::Unit::TestCase
