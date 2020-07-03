require 'spec_helper'

RSpec.describe CanaryCacheStore::Canaryable do
  module Dummy
    class MemoryCacheStore < ActiveSupport::Cache::MemoryStore
      include CanaryCacheStore::Canaryable
    end
  end

  let(:canary_store) { CanaryCacheStore.klass.new(size: 64.megabytes) }
  let(:default_store) { CanaryCacheStore.klass.new(size: 32.megabytes) }
  let(:rollout_percentage) { 100 }
  let(:options) do
    {
      canary: canary_store,
      default: default_store,
      rollout_percentage: rollout_percentage
    }
  end
  let(:store) do
    CanaryCacheStore.configure do |config|
      config.base_class = ActiveSupport::Cache::MemoryStore
    end
    ::Dummy::MemoryCacheStore.new(options)
  end

  describe '#initialize' do
    context 'when configure with stores' do
      it do
        expect(store.stores).to all(be_a(ActiveSupport::Cache::MemoryStore))
        expect(store.stores.length).to eq(2)
        expect(store.rollout_percentage).to eq(100)
      end
    end
  end

  describe '#read_multi' do
    let(:name) { [:a, :b, :c]}
    it 'asks for read store' do
      expect(store).to receive(:read_multi).with(*name)
      store.read_multi(*name)
    end
  end

  describe '#read_store' do
    subject { store.send(:read_store) }
    context 'when service percentage is 0' do
      let(:rollout_percentage) { 0 }
      it 'uses default store' do
        # puts "===== wtf? #{subject.inspect} vs #{default_store.inspect}, #{subject == default_store}"
        (1..100).each { is_expected.to eq(default_store) }
      end
    end

    context 'when service percentage is 100' do
      let(:rollout_percentage) { 100 }
      it 'uses canary store' do
        (1..100).each { is_expected.to eq(canary_store) }
      end
    end

    context 'when service percentage is random' do
      let(:rollout_percentage) { 50 }
      it 'call canary and default randomly' do
        allow(store).to receive(:read_canary?).and_call_original
        result = (1..1000).map { store.send(:read_store) }
        expect(result).to include(canary_store)
        expect(result).to include(default_store)
      end
    end
  end

  # Test table for write-operation tests
  {
    increment: [:key, 1, {}],
    decrement: [:key, 1, {}],
    cleanup: [{}],
    clear: [{}],
    delete_matched: [nil, {}],
    write_entry: [:key, :value, {}],
    delete_entry: [:key, {}]
  }.each do |method_name, args|
    describe "##{method_name}" do
      it 'performs in canary and default cache store' do
        expect(canary_store).to receive(method_name).with(*args)
        expect(default_store).to receive(method_name).with(*args)
        store.send(method_name, *args)
      end
    end
  end

  describe '#perform_write' do
    context 'when error occurs' do
      let(:error) { StandardError.new('Some error') }
      let(:handler) { Proc.new {} }
      it 'triggers canary store error handler' do
        CanaryCacheStore.configure do |config|
          config.on_write_error = handler
        end
        allow(default_store).to receive(:send).with(:write_entry, :test).and_raise(error)
        expect(handler).to receive(:call).with(error, hash_including(caused_by: default_store))
        store.send(:perform_write, :write_entry, :test)
      end
    end
  end

  context 'when write store is specified' do
    let(:write_store) { CanaryCacheStore.klass.new(size: 64.megabytes) }
    let(:default_store) { CanaryCacheStore.klass.new(size: 32.megabytes) }
    let(:options) do
      {
        write: write_store,
        default: default_store
      }
    end
    let(:store) do
      CanaryCacheStore.configure do |config|
        config.base_class = ActiveSupport::Cache::MemoryStore
      end
      ::Dummy::MemoryCacheStore.new(options)
    end

    # Test table for write-operation tests
    {
      increment: [:key, 1, {}],
      decrement: [:key, 1, {}],
      cleanup: [{}],
      clear: [{}],
      delete_matched: [nil, {}],
      write_entry: [:key, :value, {}],
      delete_entry: [:key, {}]
    }.each do |method_name, args|
      describe "##{method_name}" do
        it 'performs in write store but not default cache store' do
          expect(write_store).to receive(method_name).with(*args)
          expect(default_store).not_to receive(method_name).with(*args)
          store.send(method_name, *args)
        end
      end
    end
  end

  context 'when connecting with redis' do
    module Dummy
      class RedisCacheStore < ::ActiveSupport::Cache::RedisStore
        include CanaryCacheStore::Canaryable
      end
    end
    let(:store) do
      CanaryCacheStore.configure do |config|
        config.base_class = ::ActiveSupport::Cache::RedisStore
      end
      ::Dummy::RedisCacheStore.new(options)
    end
    context 'with real redis connection' do
      let(:cache_key) { "test_cache_key_#{Faker::Crypto.md5}" }
      let(:value) { rand(99999999) + 1 }
      let(:options) do
        {
          canary: [:redis_store, 'redis://127.0.0.1:6379/3', {}],
          default: [:redis_store, 'redis://127.0.0.1:6379/4', {}],
        }
      end
      shared_examples_for 'a succeed case on write' do
        it 'correctly reading/writing data' do
          expect(store.read(cache_key, { raw: using_raw })).to eq(nil)
          store.write(cache_key, value, { raw: using_raw })
          expect(store.read(cache_key, { raw: using_raw }).to_i).to eq(value)
        end
      end

      shared_examples_for 'a succeed case on fetch' do
        it 'correctly reading/writing data' do
          returned = store.fetch(cache_key, { raw: using_raw }) { value }
          expect(returned.to_i).to eq(value)
        end
      end

      describe '#write' do
        let(:using_raw) { false }
        it_behaves_like 'a succeed case on write'

        context 'with raw data' do
          let(:using_raw) { true }
          it_behaves_like 'a succeed case on write'
        end

        context 'with expiry' do
          let(:expiry) { 30.seconds }
          it 'sets correct ttl for given cache key' do
            store.write(cache_key, value, { expires_in: expiry })
            expect(store.canary_store.data.ttl(cache_key)).to be > 0
            expect(store.default_store.data.ttl(cache_key)).to be > 0
          end
        end
      end

      describe '#fetch' do
        let(:using_raw) { false }
        it_behaves_like 'a succeed case on fetch'

        context 'with raw data' do
          let(:using_raw) { true }
          it_behaves_like 'a succeed case on fetch'
        end

        context 'with expiry' do
          let(:expiry) { 30.seconds }
          it 'sets correct ttl for given cache key' do
            store.fetch(cache_key, { expires_in: expiry }) { value }
            expect(store.canary_store.data.ttl(cache_key)).to be > 0
            expect(store.default_store.data.ttl(cache_key)).to be > 0
          end
        end
      end
    end
  end
end
