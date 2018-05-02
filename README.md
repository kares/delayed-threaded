# Delayed::Threaded

Allows to start [DJ][0] in the same process using `Thread.new { ... }`

Extracted from [JRuby-Rack-Worker][1]: an effort to run Ruby workers in threads
with Java (JRuby-Rack) deployments (previously known as `Delayed::JRubyWorker`).

**NOTE: JRuby only, for now (PRs welcome)!**

## Installation

```ruby
gem 'delayed-threaded'
```

and `bundle` or install it yourself as `gem install delayed-threaded`.

## Usage

```ruby
def start_worker
  options = { :quiet => true }
  options[:queues] = (ENV['QUEUES'] || ENV['QUEUE'] || '').split(',')
  options[:min_priority] = ENV['MIN_PRIORITY']
  options[:max_priority] = ENV['MAX_PRIORITY']
  # beyond `rake delayed:work` compatibility :
  if read_ahead = ENV['READ_AHEAD'] # DEFAULT_READ_AHEAD = 5
    options[:read_ahead] = read_ahead.to_i
  end
  if sleep_delay = ENV['SLEEP_DELAY'] # DEFAULT_SLEEP_DELAY = 5
    options[:sleep_delay] = sleep_delay.to_f
  end

  worker = Delayed::Threaded::Worker.new(options)
  worker.start
rescue Exception => e
  msg = "FATAL #{e.inspect}"
  if backtrace = e.backtrace
    msg << ":\n  #{backtrace.join("\n  ")}"
  end
  STDERR.puts(msg)
end

Thread.new { start_worker }
```

## Development

After checking out the repo, run `bin/setup` to install dependencies.
Then, run `rake test` to run the tests. You can also run `bin/console` for an
interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Copyright

Copyright (c) 2018 [Karol Bucek](http://kares.org).
See LICENSE (http://en.wikipedia.org/wiki/MIT_License) for details.

[0]: https://github.com/collectiveidea/delayed_job
[1]: https://github.com/kares/jruby-rack-worker
