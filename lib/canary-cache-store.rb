require 'active_support/cache'
require 'canary-cache-store/version'
require 'canary-cache-store/canaryable'

module CanaryCacheStore
  class << self
    attr_reader :configuration
  end

  def self.configure
    @configuration ||= Configuration.new
    yield(@configuration) if block_given?
  end

  def self.klass
    unless defined?(ActiveSupport::Cache::CanaryCacheStore)
      klass = Class.new(configuration.base_class) do
        include CanaryCacheStore::Canaryable
      end
      ActiveSupport::Cache.const_set('CanaryCacheStore', klass)
    end
    ActiveSupport::Cache::CanaryCacheStore
  end

  class Configuration
    attr_accessor :base_class, :on_write_error

    def initialize
      @base_class = ActiveSupport::Cache::Store
      @on_write_error = nil
    end
  end
end
