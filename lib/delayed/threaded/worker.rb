require 'java'
require 'delayed_job' unless defined?(Delayed::Worker)
require 'socket' # due Socket.gethostname in Delayed::Worker#name

require 'delayed/threaded/sleep_calculator'
require 'delayed/threaded/sync_lifecycle'

module Delayed::Threaded
  # Threaded DJ worker implementation.
  # - inspired by Delayed::Command
  # - no daemons dependency + thread-safe
  class Worker < Delayed::Worker

    include SleepCalculator

    # @override to return the same as Delayed::Worker.lifecycle (uses class instance state)
    def self.lifecycle; Delayed::Worker.lifecycle end

    # @override since `initialize` (DJ 4.1) does: `self.class.setup_lifecycle`
    def self.setup_lifecycle; Delayed::Worker.setup_lifecycle end

    unless defined? Delayed::Worker.setup_lifecycle
      # adapt DJ 3.0/4.0 :
      # def self.lifecycle
      #   @lifecycle ||= Delayed::Lifecycle.new
      # end
      def superclass.lifecycle
        @lifecycle ||= setup_lifecycle
      end
      def superclass.setup_lifecycle
        @lifecycle = Delayed::Lifecycle.new
      end
    end

    # @patch make sure concurrent worker threads do not cause multiple initializations
    Delayed::Worker.extend SyncLifecycle if Delayed.const_defined? :Lifecycle

    THREAD_LOCAL_ACCESSORS = [ :sleep_delay, :read_ahead, :exit_on_complete,
                               :delay_jobs, :max_attempts, :default_log_level ]
    private_constant :THREAD_LOCAL_ACCESSORS if respond_to?(:private_constant)
    #
    # due Delayed::Worker#initialize(options = {}) :
    #
    # [:min_priority, :max_priority, :sleep_delay, :read_ahead, :queues, :exit_on_complete].each do |option|
    #   self.class.send("#{option}=", options[option]) if options.key?(option)
    # end
    #
    # :min_priority, :max_priority, :queues, :max_run_time, :destroy_failed_jobs
    #  ... are "always" global (accessed in backend)

    # NOTE: should we warn when 'global' options are being passed in, so that users prefer (realize)
    # they need to be setting the cattr instead e.g. `Delayed::Worker.queues = [ 'my_queue' ]` ... ?

    class Config
      attr_accessor(*THREAD_LOCAL_ACCESSORS)
      def key?(name); ! instance_variable_get(:"@#{name}").nil? end
    end

    THREAD_LOCAL_ACCESSORS.each do |name|
      class_eval(<<-EOS, __FILE__, __LINE__ + 1)
        def self.#{name}=(val)
          (Thread.current[:delayed_threaded_worker_config] ||= Config.new).#{name} = val
        end
        def self.#{name}
          if (config = Thread.current[:delayed_threaded_worker_config]) && config.key?(:#{name})
            config.#{name}
          else
            superclass.#{name}
          end
        end
        # and re-def instance accessors setup by cattr_accessor (from superclass) :        
        def #{name}=(val); self.class.#{name} = val end
      EOS
      unless [:max_attempts, :max_run_time].include?(name) # DJ::Worker#max_run_time(job)
        # re-def instance accessors setup by cattr_accessor (from superclass)
        class_eval("def #{name}; self.class.#{name} end", __FILE__, __LINE__)
      end
    end
    # e.g. :
    #
    #  def self.sleep_delay=(value)
    #    (Thread.current[:delayed_threaded_worker_config] ||= Config.new).sleep_delay = value
    #  end
    #
    #  def self.min_priority
    #    if (config = Thread.current[:delayed_threaded_worker_config]) && config.key?(:sleep_delay)
    #      config.sleep_delay
    #    else
    #      superclass.sleep_delay # Delayed::Worker.sleep_delay
    #    end
    #  end

    def name
      if (@name ||= nil).nil?
        # super - [prefix]host:hostname pid:process_pid
        begin
          @name = "#{super} thread:#{thread_id}".freeze
        rescue
          @name = "#{@name_prefix}thread:#{thread_id}".freeze
        end
      end
      @name
    end

    def to_s; name; end

    if defined? Thread.current.name
      def thread_id
        if ( name = Thread.current.name || '' ).empty?
          name = java.lang.Thread.currentThread.getName
          if name.size > 100 && match = name.match(/(.*?)\:\s.*?[\/\\]+/)
            name = match[1]
          end
        end
        name
      end
    else
      def thread_id
        # NOTE: JRuby might set a bit long name for Thread.new { ... } code e.g.
        # RubyThread-1: /home/[...]/src/test/ruby/delayed/jruby_worker_test.rb:163
        if name = java.lang.Thread.currentThread.getName
          if name.size > 100 && match = name.match(/(.*?)\:\s.*?[\/\\]+/)
            match[1]
          else
            name
          end
        end
      end
    end

    def exit!
      return if @exit # #stop?
      say "Stoping job worker"
      @exit = true # #stop
      if Delayed.const_defined?(:Job) && Delayed::Job.respond_to?(:clear_locks!)
        Delayed::Job.clear_locks!(name)
      end
    end

    unless defined? Delayed::Lifecycle # DJ 2.x (< 3.0)
      require 'benchmark'
      # in case DJ 2.1 loads AS 3.x we're need `[1,2].sum` :
      require 'active_support/core_ext/enumerable' rescue nil

      def start
        say "Starting job worker"
        trap

        loop do
          result = nil

          realtime = Benchmark.realtime do
            result = work_off
          end

          count = result.sum

          break if @exit

          if count.zero?
            sleep(self.class.sleep_delay)
          else
            say "#{count} jobs processed at %.4f j/s, %d failed ..." % [count / realtime, result.last]
          end

          break if @exit
        end
      end

      def stop?; !!@exit; end
      def stop; @exit = true; end

    end

    protected

    def trap(name = nil)
      # catch invocations from #start traps TERM and INT
      at_exit { exit! } if ! name || name.to_s == 'TERM'
    end

  end

end

Dir.chdir( Rails.root ) if defined?(Rails.root) && Dir.getwd.to_s != Rails.root.to_s

if ! Delayed::Worker.backend && ! Delayed.const_defined?(:Lifecycle)
  Delayed::Worker.guess_backend # deprecated on DJ since 3.0
end

# NOTE: no explicit logger configuration - DJ logger defaults to Rails.logger
# if this is not desired - e.g. one wants script/delayed_job's logger behavior
# it's more correct to configure in an initializer rather then forcing the use
# of delayed_job.log (like Delayed::Command does) ...
# Delayed::Worker.logger = Logger.new(File.join(Rails.root, 'log', 'delayed_job.log'))
