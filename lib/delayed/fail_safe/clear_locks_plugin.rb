require 'delayed/worker'

require 'delayed/fail_safe/clear_locks'
if defined? Delayed::Plugins::ClearLocks
  i = Delayed::Worker.plugins.index(Delayed::Plugins::ClearLocks) || 0
  Delayed::Worker.plugins[i] = Delayed::FailSafe::ClearLocks
end
