require 'spec_helper'

if ORM.has(:mongoid)
describe Promiscuous, 'bootstrapping dependencies' do
  before { use_fake_backend }
  before { load_models }
  before { run_subscriber_worker! }

  #
  # TODO Test that the bootstrap exchange is used for both Data and Version
  #

  context 'when in publisher is in bootstrapping mode' do
    before { Promiscuous::Config.downgrade_reads_to_writes = true }

    it 'read dependencies are upgraded to write dependencies' do
      pub1 = pub2 = nil
      Promiscuous.context do
        pub1 = PublisherModel.create
      end

      Promiscuous::AMQP::Fake.get_next_payload['dependencies']

      Promiscuous.context do
        PublisherModel.find(pub1.id) # PublisherModel.first for ActiveRecord
        pub2 = PublisherModel.create
      end
      dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']

      dep['read'].should == nil
      dep['write'].should == hashed["publisher_models/id/#{pub2.id}:0", "publisher_models/id/#{pub1.id}:1"]
    end
  end

  context 'when publisher is not in bootstrapping mode' do
    before { Promiscuous::Config.downgrade_reads_to_writes = false }

    it 'read dependencies are not upgraded to write dependencies' do
      pub1 = pub2 = nil
      Promiscuous.context do
        pub1 = PublisherModel.create
      end
      Promiscuous::AMQP::Fake.get_next_payload['dependencies'].inspect

      Promiscuous.context do
        PublisherModel.find(pub1.id) # PublisherModel.first for ActiveRecord
        pub2 = PublisherModel.create
      end
      dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']

      dep['read'].should  == hashed["publisher_models/id/#{pub1.id}:1"]
      dep['write'].should == hashed["publisher_models/id/#{pub2.id}:0"]
    end
  end
end

describe Promiscuous, 'bootstrapping replication' do
  before { use_real_backend }
  before { Promiscuous::Config.hash_size = 5 }
  before { load_models }
  after  { use_null_backend }

  context 'when there are no races with publishers' do
    it 'bootstraps' do
      Promiscuous::Config.downgrade_reads_to_writes = true
      Promiscuous.context { 10.times { PublisherModel.create } }

      switch_subscriber_mode(:pass1)

      Promiscuous::Publisher::Bootstrap::Version.bootstrap
      Promiscuous::Config.downgrade_reads_to_writes = false

      sleep 1

      switch_subscriber_mode(:pass2)

      Promiscuous::Publisher::Bootstrap::Data.setup
      Promiscuous::Publisher::Bootstrap::Data.run

      eventually { SubscriberModel.count.should == PublisherModel.count }

      switch_subscriber_mode(false)

      PublisherModel.all.each { |pub| Promiscuous.context { pub.update_attributes(:field_1 => 'ohai') } }

      eventually { SubscriberModel.each { |sub| sub.field_1.should == 'ohai' } }
    end
  end

  context 'when updates happens during the version boostrapping' do
    it 'bootstraps' do
      stub_before_hook(Promiscuous::Publisher::Bootstrap::Version::Chunk, :fetch_and_send) do |control|
        Promiscuous.context do
          # generating lots of dependencies to force us to touch different shards
          PublisherModel.each { }
          PublisherModel.create
        end
      end

      Promiscuous::Config.logger.level = Logger::FATAL

      Promiscuous.context { 10.times { PublisherModel.create } }
      switch_subscriber_mode(:pass1)
      Promiscuous::Config.downgrade_reads_to_writes = true
      Promiscuous::Publisher::Bootstrap::Version.bootstrap
      Promiscuous::Config.downgrade_reads_to_writes = false
      sleep 1
      switch_subscriber_mode(:pass2)
      Promiscuous::Publisher::Bootstrap::Data.setup
      Promiscuous::Publisher::Bootstrap::Data.run

      eventually { SubscriberModel.count.should == PublisherModel.count }

      switch_subscriber_mode(false)
      PublisherModel.all.each { |pub| Promiscuous.context { pub.update_attributes(:field_1 => 'ohai') } }
      eventually { SubscriberModel.each { |sub| sub.field_1.should == 'ohai' } }
    end
  end

  context 'when updates happens after the version bootstrap, but before the document is replicated' do
    it 'bootstraps' do
      Promiscuous::Config.downgrade_reads_to_writes = true
      Promiscuous.context { 10.times { PublisherModel.create } }

      switch_subscriber_mode(:pass1)

      Promiscuous::Publisher::Bootstrap::Version.bootstrap
      sleep 1
      Promiscuous::Config.downgrade_reads_to_writes = false

      Promiscuous.context { PublisherModel.first.update_attributes(:field_2 => 'hello') }

      switch_subscriber_mode(:pass2)

      Promiscuous::Publisher::Bootstrap::Data.setup
      Promiscuous::Publisher::Bootstrap::Data.run

      eventually do
        SubscriberModel.count.should == PublisherModel.count
        SubscriberModel.first.field_2.should == 'hello'
      end

      switch_subscriber_mode(false)

      PublisherModel.all.each { |pub| Promiscuous.context { pub.update_attributes(:field_1 => 'ohai') } }

      eventually { SubscriberModel.each { |sub| sub.field_1.should == 'ohai' } }
    end
  end

  context 'when updates happens after the data bootstrap, but before the bootstrap mode is turned off' do
    it 'bootstraps' do
      Promiscuous::Config.downgrade_reads_to_writes = true
      Promiscuous.context { 10.times { PublisherModel.create } }

      switch_subscriber_mode(:pass1)

      Promiscuous::Publisher::Bootstrap::Version.bootstrap
      sleep 1
      Promiscuous::Config.downgrade_reads_to_writes = false

      switch_subscriber_mode(:pass2)

      Promiscuous::Publisher::Bootstrap::Data.setup
      Promiscuous::Publisher::Bootstrap::Data.run

      eventually do
        SubscriberModel.count.should == PublisherModel.count
      end

      Promiscuous.context { PublisherModel.first.update_attributes(:field_2 => 'hello') }

      sleep 1

      SubscriberModel.first.field_2.should == nil

      switch_subscriber_mode(false)

      eventually { SubscriberModel.first.field_2.should == 'hello' }
    end
  end
end
end

def switch_subscriber_mode(bootstrap_mode)
  Promiscuous::Config.configure { |config| config.bootstrap = bootstrap_mode }
  if @worker
    @worker.pump.recover # send the nacked message again
  else
    run_subscriber_worker!
  end
end
