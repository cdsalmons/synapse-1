require 'spec_helper'

if ORM.has(:polymorphic)
describe Promiscuous do
  # app_a -> app_b -> app_c
  #       \--------/
  # We are looking from the pub_b point of view

  context 'when having a dependency on a subscribed table' do
    before do
      define_constant 'User' do
        include Mongoid::Document
        include Promiscuous::Decorator

        subscribe :as => 'User', :from => :app_a do
          field :name
        end

        publish do
          field :num_posts
        end
      end

      define_constant 'Post' do
        include Mongoid::Document
        include Promiscuous::Publisher

        publish do
          field :content
          belongs_to :user
        end
      end
    end

    context 'when referencing an external class' do
      before { use_fake_backend { |config| config.app = 'app_b' } }

      it 'publishes the right external dependencies' do
        user = without_promiscuous { User.create(:name => 'john') }

        user = post = nil
        Promiscuous.context do
          user = User.first
          post = Post.create(:user => user, :content => 'ohai')
        end

        payload = Promiscuous::AMQP::Fake.get_next_payload

        dep = payload['dependencies']
        payload['operations'].first['attributes'].should == {'content' => 'ohai', 'user_id' => user.id.to_s}
        dep['read'].should  == hashed["users/id/#{user.id}:0"]
        dep['write'].should == hashed["posts/id/#{post.id}:0"]
        dep['external'].should == hashed["app_a:users/id/#{user.id}:0"]
      end
    end

    context 'when decorating' do
      before { use_fake_backend { |config| config.app = 'app_b' } }

      it 'publishes the right external dependencies' do
        user = without_promiscuous { User.create(:name => 'john') }

        Promiscuous.context do
          user = User.first
          user.update_attributes!(:num_posts => 3)
        end

        payload = Promiscuous::AMQP::Fake.get_next_payload

        dep = payload['dependencies']
        payload['operations'].first['attributes'].should == {'num_posts' => 3}
        dep['read'].should  == nil
        dep['write'].should == hashed["users/id/#{user.id}:0"]
        dep['external'].should == hashed["app_a:users/id/#{user.id}:0"]
      end
    end
  end

  context 'when replicating' do
    def with_app(app_name, &block)
      @definitions ||= {}
      @definitions[app_name.to_s] = block
    end

    def switch_to(app, &block)
      app = app.to_s
      @workers.values.each(&:pause)

      cleanup_constants
      Promiscuous::Loader.cleanup

      Promiscuous::Config.app = app
      @definitions[app].call
      block.call if block

      @workers[app].try(:resume)
    end

    def bootstrap_apps
      @workers = Hash[@definitions.keys.map do |app|
        Promiscuous::Config.queue_name = app
        [app, Promiscuous::Subscriber::Worker.new.tap { |w| w.start }]
      end]
    end

    def shutdown_apps
      @workers.values.each(&:stop)
    end

    before do
      with_app :app_a do
        define_constant 'A::User' do
          include Mongoid::Document
          include Promiscuous::Publisher

          publish do
            field :name
          end
        end
      end

      with_app :app_b do
        define_constant 'B::User' do
          include Mongoid::Document
          include Promiscuous::Decorator

          subscribe :as => 'A::User', :from => :app_a, :parent_collection => 'a_users' do
            field :name
          end

          publish do
            field :is_spammer
          end
        end
      end

      with_app :app_c do
        define_constant 'C::User' do
          include Mongoid::Document
          include Promiscuous::Subscriber

          subscribe :as => 'A::User', :from => :app_a, :parent_collection => 'a_users' do
            field :name
          end

          subscribe :as => 'B::User', :from => :app_b, :parent_collection => 'b_users' do
            field :is_spammer
          end
        end
      end
    end

    before { use_real_backend }
    before { bootstrap_apps }
    after  { shutdown_apps }
    after  { use_fake_backend }

    it 'replicates' do
      switch_to :app_a
      Promiscuous.context do
        A::User.create(:name => 'john')
      end

      switch_to :app_b
      eventually do
        B::User.first.name.should == 'john'
      end
      Promiscuous.context do
        B::User.first.update_attributes!(:is_spammer => true)
      end

      switch_to :app_c
      eventually do
        u = C::User.first
        u.name.should == 'john'
        u.is_spammer.should == true
      end
    end

    it 'preserves ordering' do
      switch_to :app_a
      Promiscuous.context do
        A::User.create(:name => 'john')
      end

      switch_to :app_b
      eventually do
        B::User.first.name.should == 'john'
      end

      # App b is going to send an impossible external dependency to c
      dep = Promiscuous::Dependency.parse("a_users/id/#{B::User.first.id}", :owner => 'app_a')
      dep.redis_node.incr(dep.key(:sub).join('rw'))

      Promiscuous.context do
        B::User.first.update_attributes!(:is_spammer => true)
      end

      switch_to :app_c
      u = nil
      eventually do
        u = C::User.first
        u.name.should == 'john'
      end
      sleep 0.5
      u.is_spammer.should == nil
    end

    it 'replicates when using callbacks' do
      switch_to :app_a
      Promiscuous.context do
        A::User.create(:name => 'john')
      end

      switch_to :app_b do
        B::User.before_save do
          self.is_spammer = true
        end
      end

      eventually do
        B::User.first.name.should == 'john'
      end

      switch_to :app_c
      eventually do
        u = C::User.first
        u.name.should == 'john'
        u.is_spammer.should == true
      end
    end

  end
end
end
