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
  if read_ahead = ENV['READ_AHEAD'] # DEFAULT_READ_AHEAD = 5
    options[:read_ahead] = read_ahead.to_i
  end
  if sleep_delay = ENV['SLEEP_DELAY'] # DEFAULT_SLEEP_DELAY = 5
    options[:sleep_delay] = sleep_delay.to_f
  end

  # some options are set to work per-thread (as a thread-local).
  worker = Delayed::Threaded::Worker.new(options)
  worker.start
rescue Exception => e
  msg = "FATAL #{e.inspect}"
  if backtrace = e.backtrace
    msg << ":\n  #{backtrace.join("\n  ")}"
  end
  STDERR.puts(msg)
end

# while other options are global and do not make sense to be set per-thread
Delayed::Worker.queues = (ENV['QUEUES'] || ENV['QUEUE'] || '').split(',')
Delayed::Worker.min_priority = ENV['MIN_PRIORITY'] if ENV['MIN_PRIORITY']
Delayed::Worker.max_priority = ENV['MAX_PRIORITY'] if ENV['MAX_PRIORITY']

Thread.new { start_worker }
```

### ActiveRecord

There's an optional integration with the [ActiveRecord][2] backend, to clear
the connections after work (as the worker sleeps), setup as a plugin using :

```ruby
require 'delayed/active_record/release_connection_plugin.rb'
````

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
[2]: https://github.com/collectiveidea/delayed_job_active_record
