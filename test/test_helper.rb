$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require 'delayed/threaded'

gem 'test-unit' # uninitialized constant Test::Unit::TestResult::TestResultFailureSupport
require 'test/unit'
require 'test/unit/context'
begin; require 'mocha/setup'; rescue LoadError; require 'mocha'; end

TestImpl = Test::Unit::TestCase
