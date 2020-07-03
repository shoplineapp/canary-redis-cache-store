require 'active_support/concern'
require 'monitor'

module CanaryCacheStore
  module Canaryable
    extend ActiveSupport::Concern

    included do
      extend ClassMethods

      attr_reader :stores, :default_store, :canary_store, :write_store, :rollout_percentage

      def initialize(options = nil)
        options ||= {}
        
        super

        @monitor = Monitor.new

        @rollout_percentage = options[:rollout_percentage] || 0

        @stores = %i[canary default write].map do |key|
          config = options[key.to_sym] || {}
          next if config.blank?

          if config.is_a?(ActiveSupport::Cache::Store)
            store = config
          else
            raise "Unknown cache store" unless config.is_a?(Array) && config.try(:[], 0).is_a?(Symbol)
            store = "::ActiveSupport::Cache::#{config.try(:[], 0).to_s.camelize}".constantize.new(*(config.try(:[], (1..-1)) || []))
          end
          instance_variable_set("@#{key}_store".to_sym, store)

          store
        end.compact
      end

      def read_multi(*names)
        read_store.read_multi(*names)
      end

      def delete_matched(matcher, options = nil)
        perform_write(__method__, matcher, options)
        true
      end

      %i[increment decrement].each do |name|
        define_method(name) do |*args|
          nums = perform_write(__method__, *args)
          nums.detect {|n| !n.nil?}
        end
      end

      %i[cleanup clear].each do |name|
        define_method(name) do |*args|
          perform_write(__method__, *args)
        end
      end

      def read_entry(key, options = nil)
        read_store.send(:read_entry, key, options)
      end

      private

      attr_reader :monitor

      def read_store
        read_canary? ? canary_store : default_store
      end

      def read_canary?
        @canary_store.present? && rand(100) < rollout_percentage
      end

      def synchronize(&block)
        monitor.synchronize(&block)
      end

      def perform_write(action, *args)
        writable_stores = @write_store.present? ? [@write_store] : stores
        synchronize do
          writable_stores.map do |store|
            begin
              store.send(action, *args)
            rescue StandardError => ex
              if CanaryCacheStore.configuration.on_write_error.is_a?(Proc)
                CanaryCacheStore.configuration.on_write_error.call(ex, caused_by: store)
              end
              nil
            end
          end
        end
      end

      %i[write_entry delete_entry].each do |name|
        define_method(name) do |*args|
          perform_write(__method__, *args)
          true
        end
      end
    end

    module ClassMethods
      
    end
  end
end
