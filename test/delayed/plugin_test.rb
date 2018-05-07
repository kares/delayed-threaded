require File.expand_path('test_helper', File.dirname(__FILE__) + '/..')

require 'delayed/threaded/worker'

module Delayed
  class PluginTest < TestImpl

    def self.load_plugin!
      load_plugin_like!
      require 'delayed_cron_job' # order is important - backend needs to be loaded
      # gem: spec.add_dependency "delayed_job", ">= 4.1"
    end

    def self.load_plugin_like!
      load_active_record!

      require 'delayed_job_active_record' # DJ 3.0+

      require 'delayed/active_record/release_connection_plugin.rb'
    end

    def self.undo_plugin!
      # Delayed::Backend::ActiveRecord::Job.send(:include, DelayedCronJob::Backend::UpdatableCron)
      # def self.included(klass)
      #   klass.send(:before_save, :set_next_run_at, :if => :cron_changed?)
      # end
      Delayed::Backend::ActiveRecord::Job.skip_callback :save, :before, :set_next_run_at
      # Delayed::Backend::ActiveRecord::Job.attr_accessible(:cron)
      #
      # Delayed::Worker.plugins << DelayedCronJob::Plugin
      Delayed::Worker.plugins.delete DelayedCronJob::Plugin if defined? DelayedCronJob::Plugin
    end

    setup do
      require 'logger'; require 'stringio'
      Delayed::Worker.logger = Logger.new(StringIO.new)
    end

    test "hooks up SyncLifecycle" do
      assert Delayed::Worker.is_a?(Delayed::Threaded::SyncLifecycle)
    end if defined? Delayed::Plugin

    test "only one lifecycle instance is created" do
      self.class.load_plugin_like!

      lifecycle = Delayed::Lifecycle.new
      Delayed::Lifecycle.expects(:new).returns(lifecycle).once
      begin
        reset_worker
        threads = start_threads(3) do
          l1 = Delayed::Threaded::Worker.lifecycle
          l2 = Delayed::Worker.lifecycle
          assert_same l2, l1
        end
        threads.each(&:join)
      ensure
        Delayed::Worker.reset # @lifecycle = nil
      end
    end if Delayed::Worker.is_a?(Delayed::Threaded::SyncLifecycle)

    test "setup lifecycle does guard for lifecycle creation" do
      self.class.load_plugin_like!

      lifecycle = Delayed::Lifecycle.new
      Delayed::Lifecycle.expects(:new).returns(lifecycle).once
      begin
        reset_worker
        threads = start_threads(5) do
          Delayed::Threaded::Worker.new
          sleep 0.1
          Delayed::Worker.new
        end
        threads.each(&:join)
      ensure
        Delayed::Worker.reset # @lifecycle = nil
      end
    end if Delayed::Worker.is_a?(Delayed::Threaded::SyncLifecycle)

    context "with backend" do

      @@plugin = nil

      def self.startup
        Delayed::Worker.logger = Logger.new(STDOUT)
        Delayed::Worker.logger.level = Logger::DEBUG
        ActiveRecord::Base.logger = Delayed::Worker.logger if $VERBOSE

        load_active_record!
        load 'delayed/active_record_schema_cron.rb'
        Delayed::Job.reset_column_information

        @@plugin = begin; load_plugin!; rescue Exception => ex; ex end
      end

      def self.shutdown; undo_plugin! end

      teardown { $worker = nil }

      class CronJob

        def initialize(param); @param = param end

        @@performed = nil
        def perform
          puts "#{self}#perform param = #{@param}"
          raise "already performed" if @@performed
          @@performed = @param
        end

      end

      test "works (integration)" do
        omit "#{@@plugin.inspect}" if @@plugin.is_a?(Exception) # 'plugin not supported on DJ < 4.1'

        Thread.start do
          $worker = Delayed::Threaded::Worker.new({ :sleep_delay => 0.10 })

          Thread.current.abort_on_exception = true;
          $worker.start
        end

        start = Time.now
        Delayed::Job.enqueue job = CronJob.new(:boo), cron: '0-59/1 * * * *'
        Delayed::Job.where('cron IS NOT NULL').first.update_column(:run_at, Time.now)

        sleep(0.25)
        assert ! $worker.stop?

        assert_equal :boo, CronJob.send(:class_variable_get, :'@@performed')

        sleep(0.30)
        # it's re-scheduled for next run :
        assert job = Delayed::Job.where('cron IS NOT NULL').first
        #puts job.inspect if $VERBOSE
        min = start.min; min_next = min + 1; min_next = 0 if min_next == 60
        assert [min, min_next].include?(job.run_at.min)

        $worker.stop
        sleep(0.15)
        assert $worker.stop?
      end

      class SampleJob

        def initialize(param); @param = param end

        @@performed = nil
        def perform
          puts "#{self}#perform param = #{@param}"
          @@performed = @param
        end

        def self.performed; @@performed end

      end

      class HookableWorker < Delayed::Threaded::Worker

        NIL = lambda { |_| }

        def before_work_off(&hook); @before_work_off = hook end
        def after_work_off(&hook); @after_work_off = hook end

        def work_off(num = 100)
          (@before_work_off ||= NIL).call(self)
          super(num).tap do
            (@after_work_off ||= NIL).call(self)
          end
        end

        def sleep(delay)
          puts "\nsleep(#{delay})" if $VERBOSE
          super(delay)
        end

      end

      test "clears thread-bound AR connection (integration)" do
        omit "#{@@plugin.inspect}" if @@plugin.is_a?(Exception) # 'plugin not supported on DJ < 4.1'

        Delayed::Job.enqueue job = SampleJob.new(:muu1)

        Thread.start do
          $worker = HookableWorker.new(:sleep_delay => 0.05) # thread-local
          $worker.before_work_off do
            puts "\nbefore_work_off hook" if $VERBOSE
            assert ! ActiveRecord::Base.connection_pool.active_connection?
          end

          Thread.current.abort_on_exception = true
          assert ! ActiveRecord::Base.connection_pool.active_connection?
          $worker.start
          assert ! ActiveRecord::Base.connection_pool.active_connection?
        end
        sleep(0.20)

        assert_equal :muu1, SampleJob.performed

        Delayed::Job.enqueue job = SampleJob.new(:muu2)

        sleep(0.20)

        assert_equal :muu2, SampleJob.performed

        $worker.stop
      end

    end

    private

    def start_threads(count)
      raise 'no block' unless block_given?
      threads = []
      count.times do
        threads << Thread.start do
          begin
            yield
          rescue Exception => ex
            puts ex.inspect + "\n  #{ex.backtrace.join("\n  ")}"
          end
        end
      end
      threads
    end

    def reset_worker
      # Worker.reset only does `@lifecycle = nil` on DJ 4.1
      Delayed::Worker.instance_variable_set :@lifecycle, nil
      Delayed::Worker.reset
    end

  end
end
