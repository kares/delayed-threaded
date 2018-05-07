module Delayed
  module FailSafe
    class ClearLocks < Plugin

      @@exception_handler = lambda do |ex, worker| # fail-safe by default
        worker.say "Error running clear_locks! callback: #{ex.inspect}", 'error'
      end

      # Allow user customizations of error handling.
      #
      # To get the same behavior as `Delayed::Plugins::ClearLocks` :
      #
      #   Delayed::FailSafe::ClearLocks.exception_handler { |ex| raise(ex) }
      #
      def self.exception_handler(&block)
        return @@exception_handler unless block_given?
        @@exception_handler = block
      end

      def self.call(worker)
        Delayed::Job.clear_locks!(worker.name)
      rescue => ex
        @@exception_handler.call(ex, worker)
      end

      callbacks do |lifecycle|
        lifecycle.around(:execute) do |worker, &block|
          begin
            block.call(worker)
          ensure
            ClearLocks.call(worker)
          end
        end
      end

    end
  end
end