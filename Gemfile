source "https://rubygems.org"

gemspec

if ENV['delayed_job']
  if ENV['delayed_job'] == 'master'
    gem 'delayed_job', :git => 'git://github.com/collectiveidea/delayed_job.git'
    gem 'delayed_job_active_record', :require => nil
  else
    gem 'delayed_job', version = ENV['delayed_job']
    unless version =~ /~?\s?2\.\d/ # delayed_job_active_record only for DJ >= 3.0
      gem 'delayed_job_active_record', :require => nil
    end
    if version =~ /~?\s?4\.[1]/ # add_dependency "delayed_job", ">= 4.1"
      gem 'delayed_cron_job', :require => nil
    end
  end
else
  gem 'delayed_job'
  gem 'delayed_job_active_record', :require => nil
  gem 'delayed_cron_job', :require => nil
end

if ENV['activerecord']
  gem 'activerecord', ENV['activerecord'], :require => nil
else
  gem 'activerecord', :require => nil # for tests
end

gem 'activerecord-jdbcsqlite3-adapter', '~> 1.3.20', :require => nil, :platform => :jruby
