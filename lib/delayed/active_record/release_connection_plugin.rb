require 'delayed/worker'

require 'delayed/backend/active_record/release_connection'
Delayed::Worker.plugins << Delayed::Backend::ActiveRecord::ReleaseConnection
