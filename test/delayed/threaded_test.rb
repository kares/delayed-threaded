require File.expand_path('test_helper', File.dirname(__FILE__) + '/..')

class Delayed::ThreadedTest < TestImpl
  def test_that_it_has_a_version_number
    refute_nil ::Delayed::Threaded::VERSION
  end
end
