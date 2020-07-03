# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)
require 'canary-cache-store/version'

Gem::Specification.new do |s|
  s.name        = 'canary-cache-store'
  s.version     = CanaryCacheStore::VERSION
  s.authors     = ['Philip Yu']
  s.email       = ['philip@shoplineapp.com']
  s.homepage    = 'https://shopline.hk'
  s.summary     = 'Rails cache store to perform double-write and random-read on canary cache'
  s.description = 'Rails cache store to perform double-write and random-read on canary cache'
  s.license     = 'MIT'

  s.files = Dir['{lib}/**/*', 'MIT-LICENSE', 'README.md']
  s.test_files = Dir['spec/**/*']
  s.require_paths = ['lib']

  s.add_dependency 'activesupport'
end
