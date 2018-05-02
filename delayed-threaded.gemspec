# coding: utf-8

Gem::Specification.new do |spec|
  spec.name          = "delayed-threaded"
  spec.authors       = ["Karol Bucek"]
  spec.email         = ["self@kares.org"]
  spec.licenses      = ['MIT']

  path = File.expand_path('lib/delayed/threaded/version.rb', File.dirname(__FILE__))
  spec.version = File.read(path).match( /.*VERSION\s*=\s*['"](.*)['"]/m )[1]

  spec.summary       = %q{Making Delayed::Job a polite (thread-safe) in process citizen.}
  spec.description   = "Allows to start DJ in the same process using Thread.new { ... } "
  spec.homepage      = "https://github.com/kares/delayed-threaded"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|temp)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency "delayed_job", ">= 3.0", "< 4.2"

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "test-unit", "~> 2.5.3"
  spec.add_development_dependency "test-unit-context"
  spec.add_development_dependency "mocha"
end
