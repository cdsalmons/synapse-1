require 'spec_helper'

describe Promiscuous do
  before { load_ephemerals; load_observers }
  before { use_real_backend }
  before { run_subscriber_worker! }
  before { Promiscuous::Config.hash_size = BackendHelper::NUM_SHARDS }
  before { ModelEphemeral.track_dependencies_of :field_1 }

  context 'when using multiple redis' do
    it 'works' do
      record_callbacks(ModelObserver)

      pubs = 10.times.map { |i| ModelEphemeral.new(:id => i, :field_1 => i) }

      10.times.map do |thread_id|
        Thread.new do
          Promiscuous.context do
            10.times do |i|
              pubs.sample(5).each(&:read)
              pubs.sample.save
            end
          end
        end
      end.each(&:join)

      eventually { ModelObserver.num_saves.should == 100 }
    end
  end
end
