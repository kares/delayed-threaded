module Delayed
  module Backend
    module ActiveRecord

      # Plugin responsible for releasing ActiveRecord connections.
      # Connection (mapped to the current worker thread) gets cleared
      # as the worker finishes a 'work' iteration and goes to sleep.
      # Expected to be compatibile with AR versions 4.x/5.x.
      #
      # `Delayed::Worker.plugins << Delayed::Backend::ActiveRecord::ReleaseConnection`
      #
      # @note Should be the last one in the plugin list.
      # @note `require 'delayed/active_record/release_connection_plugin.rb'`
      #
      class ReleaseConnection < Delayed::Plugin

        def self.call(_)
          ::ActiveRecord::Base.clear_active_connections!
          # ~ connection_pool_list.each(&:release_connection)
        end

        callbacks do |lifecycle|
          lifecycle.after(:loop, &method(:call)) # (worker) work loop
          lifecycle.after(:execute, &method(:call)) # once as (worker) stops
        end

      end
    end
  end
end
