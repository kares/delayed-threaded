require File.expand_path('test_helper', File.dirname(__FILE__) + '/../..')

require 'delayed/threaded/worker'

module Delayed
  class WorkerTest < TestImpl

    setup do
      require "logger"; require 'stringio'
      Delayed::Worker.logger = Logger.new(StringIO.new)
    end

    test "new works with a hash" do
      assert_nothing_raised do
        Delayed::Threaded::Worker.new({})
      end
    end

    test "name includes thread name" do
      name = java.lang.Thread.currentThread.name
      assert_match /#{name}/, new_worker.name
    end

    test "name can be changed and reset" do
      worker = new_worker
      assert_not_nil worker.name
      worker.name = 'foo-bar'
      assert_equal 'foo-bar', worker.name
      worker.name = nil
      assert_match /^host:.*?thread:.*?/, worker.name
    end

    test "loops on start" do
      worker = new_worker
      worker.expects(:loop).once
      stub_Delayed_Job
      worker.start
    end

    test "traps (signals) on start" do
      worker = new_worker
      worker.expects(:trap).at_least_once
      worker.stubs(:loop)
      stub_Delayed_Job
      worker.start

      assert_equal worker.class, new_worker.method(:trap).owner
    end

    test "sets up an at_exit hook on start" do
      worker = new_worker
      worker.stubs(:loop)
      worker.expects(:at_exit).once
      stub_Delayed_Job
      worker.start
    end

    test "exit worker from at_exist registered hook and clears locks" do
      worker = new_worker
      def worker.at_exit(&block)
        @_at_exit_block = block
      end
      def worker.call_at_exit
        @_at_exit_block.call
      end
      worker.stubs(:loop)

      job_class = stub_Delayed_Job(:mock) # Delayed::Job
      job_class.expects(:clear_locks!).with(worker.name).at_least_once

      worker.start
      assert ! worker.stop?

      worker.call_at_exit
      assert_true worker.stop?
    end

    test "name is made of [prefix] host pid and thread" do
      worker = nil; lock = java.lang.Object.new
      thread = java.lang.Thread.new do
        begin
          worker = new_worker
          worker.name_prefix = 'PREFIX '
          worker.name
        ensure
          lock.synchronized { lock.notify }
        end
      end
      thread.name = 'worker_2'
      thread.start
      lock.synchronized { lock.wait }

      # prefix host pid thread
      parts = worker.name.split(' ')
      assert_equal 4, parts.length, parts.inspect
      require 'socket'
      assert_equal 'PREFIX', parts[0]
      assert_equal 'host:' + Socket.gethostname, parts[1]
      assert_equal 'pid:' + Process.pid.to_s, parts[2]
      assert_equal 'thread:worker_2', parts[3]
    end

    test "worker thread_id" do
      thread_id = Thread.start { new_worker.thread_id }.value
      assert ! thread_id.empty? # e.g. "Ruby-0-Thread-1: test/delayed/threaded/worker_test.rb:105"

      if defined? Thread.current.name
        thread_id = Thread.start { Thread.current.name = 'worker-0'; new_worker.thread_id }.value
        assert_equal 'worker-0', thread_id # let's assume user knows what his doing setting Thread#name
      end
    end

    test "to_s is worker name" do
      worker = new_worker
      worker.name_prefix = '42'
      assert_equal worker.name, worker.to_s
    end

    test "performs the reserved job on start" do
      worker = new_worker
      worker.stubs(:loop).yields
      worker.stubs(:at_exit)

      job_class = stub_Delayed_Job # Delayed::Job
      job_counter = 0
      job_class.expects(:reserve).at_least_once.with(worker).returns do
        job = mock("job-#{job_counter += 1}")
        job.expects(:perform).once
        job
      end

      worker.start
    end

    test "replaces class options with thread-local ones" do
      worker = nil; failure = nil; lock = java.lang.Object.new
      exit_on_cmplt = Delayed::Worker.respond_to?(:exit_on_complete)
      thread = java.lang.Thread.new do
        begin
          worker = new_worker :sleep_delay => 11, :exit_on_complete => false
          assert_equal 11, worker.class.sleep_delay
          assert_equal 11, worker.sleep_delay
          assert_equal false, worker.class.exit_on_complete if exit_on_cmplt

          assert_equal 5, Delayed::Worker.sleep_delay
          assert_equal true, Delayed::Worker.delay_jobs
          assert_equal nil, Delayed::Worker.exit_on_complete if exit_on_cmplt

          assert_equal true, worker.class.delay_jobs
          assert_equal true, worker.delay_jobs
          assert_equal 25, worker.class.max_attempts

          assert_equal 11, worker.class.sleep_delay
          assert_equal false, worker.class.exit_on_complete if exit_on_cmplt

          worker = new_worker :exit_on_complete => true
          assert_equal 11, worker.class.sleep_delay
          assert_equal true, worker.class.exit_on_complete if exit_on_cmplt

          assert_equal nil, Delayed::Worker.exit_on_complete if exit_on_cmplt
        rescue => e
          failure = e
        ensure
          lock.synchronized { lock.notify }
        end
      end

      assert_equal 5, Delayed::Worker.sleep_delay
      assert_equal true, Delayed::Worker.delay_jobs
      assert_equal nil, Delayed::Worker.exit_on_complete if exit_on_cmplt

      thread.name = 'worker_x'; thread.start

      assert_equal 5, Delayed::Worker.sleep_delay
      assert_equal nil, Delayed::Worker.exit_on_complete if exit_on_cmplt

      lock.synchronized { lock.wait }

      raise failure unless failure.nil?

      assert_equal 5, Delayed::Worker.sleep_delay
      assert_equal nil, Delayed::Worker.exit_on_complete if exit_on_cmplt
    end

    test "preserver DJ::Worker API" do
      worker = new_worker
      job = mock('delayed-job')
      job.expects(:max_attempts).returns(nil)
      job.expects(:max_run_time).returns(nil)

      assert_equal Delayed::Worker::DEFAULT_MAX_ATTEMPTS, worker.max_attempts(job)
      assert_equal Delayed::Worker::DEFAULT_MAX_RUN_TIME, worker.max_run_time(job)
    end

    begin

      context "with backend" do

        def self.startup
          load_active_record!
          # NOTE: due 'heavy' DJ plugin interference its really hard to undo
          # the plugin loading - which in case of a suite run (`rake test`)
          # gets problematic. this tests should still work standalone !
          #load 'delayed/active_record_schema.rb'
          load 'delayed/active_record_schema_cron.rb'
          #class Delayed::Job < ActiveRecord::Base; end
          begin
            require 'delayed_job_active_record' # DJ 3.0+
            Delayed::Job.reset_column_information
          rescue LoadError
            Delayed::Worker.backend = :active_record
          end
        end

        setup do
          Delayed::Worker.logger = Logger.new(STDOUT)
          Delayed::Worker.logger.level = Logger::DEBUG
          ActiveRecord::Base.logger = Delayed::Worker.logger if $VERBOSE
        end

        class TestJob

          def initialize(param)
            @param = param
          end

          @@performed = nil

          def perform
            puts "#{self}#perform param = #{@param}"
            raise "already performed" if @@performed
            @@performed = @param
          end

          def self.performed; @@performed end

        end

        test "works (integration)" do
          worker = Delayed::Threaded::Worker.new

          Delayed::Job.enqueue job = TestJob.new(:huu)
          Thread.start { Thread.current.abort_on_exception = true; worker.start }
          sleep(0.15)
          assert ! worker.stop?

          assert_equal :huu, TestJob.performed

          worker.stop
          sleep(0.10)
          assert worker.stop?
        end

      end

    end

    private

    def new_worker(options = {})
      Delayed::Threaded::Worker.new options
    end

    def stub_Delayed_Job(mock = false)
      if Delayed.const_defined?(:Job)
        Delayed.const_set :JobReal, Delayed::Job
        Delayed.send(:remove_const, :Job)
      end
      Delayed.const_set :Job, const = ( mock ? mock('Delayed::Job') : stub(:clear_locks! => nil) )
      const
    end

    teardown do
      if Delayed.const_defined?(:Job) && defined?(Mocha) && Delayed::Job.is_a?(Mocha::Mock)
        Delayed.send(:remove_const, :Job)
        if Delayed.const_defined?(:JobReal)
          Delayed.const_set :Job, Delayed::JobReal
          Delayed.send(:remove_const, :JobReal)
        end
      end
    end

  end
end
