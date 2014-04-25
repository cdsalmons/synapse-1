class PromiscuousMigration < ActiveRecord::Migration
  TABLES = [:publisher_models, :publisher_model_others,
            :subscriber_models, :subscriber_model_others,
            :publisher_dsl_models, :subscriber_dsl_models,
            :publisher_another_dsl_models, :subscriber_another_dsl_models,
            :publisher_model_belongs_tos, :subscriber_model_belongs_tos]

  def change
    [:publisher_models, :publisher_model_others,
     :subscriber_models, :subscriber_model_others,
     :publisher_dsl_models, :subscriber_dsl_models,
     :publisher_another_dsl_models, :subscriber_another_dsl_models].each do |table|
      create_table table, :force => true do |t|
        t.string :field_1
        t.string :field_2
        t.string :field_3
        t.string :child_field_1
        t.string :child_field_2
        t.string :child_field_3
        t.integer :publisher_id
      end

      create_table :publisher_model_belongs_tos, :force => true do |t|
        t.integer :publisher_model_id
      end

      create_table :subscriber_model_belongs_tos, :force => true do |t|
        t.integer :publisher_model_id
      end
    end
  end

  migrate :up
end

module ModelsHelper
  def db_purge!
    PromiscuousMigration::TABLES.each do |table|
      ActiveRecord::Base.connection.exec_delete("DELETE FROM #{table}", "Cleanup", [])
    end
  end

  def load_models
    define_constant :PublisherModel, ActiveRecord::Base do
      include Promiscuous::Publisher
      publish :field_1, :field_2, :field_3
    end

    define_constant :PublisherModelOther, ActiveRecord::Base do
      include Promiscuous::Publisher
      publish :field_1, :field_2, :field_3
    end

    define_constant :PublisherModelChild, PublisherModel do
      publish :child_field_1, :child_field_2, :child_field_3
    end

    define_constant('Scoped::ScopedPublisherModel', PublisherModel) do
    end

    define_constant :PublisherDslModel, ActiveRecord::Base do
    end

    define_constant :PublisherModelBelongsTo, ActiveRecord::Base do
      include Promiscuous::Publisher

      publish do
        belongs_to :publisher_model
      end
    end

    ##############################################

    define_constant :SubscriberModel, ActiveRecord::Base do
      include Promiscuous::Subscriber
      subscribe :field_1, :field_2, :field_3, :as => :PublisherModel, :from => :test
    end

    define_constant :SubscriberModelOther, ActiveRecord::Base do
      include Promiscuous::Subscriber
      subscribe :field_1, :field_2, :field_3, :as => :PublisherModelOther, :from => :test
    end

    define_constant :SubscriberModelChild, SubscriberModel do
      subscribe :child_field_1, :child_field_2, :child_field_3,
                :as => :SubscriberModelChild, :from => :test
    end

    define_constant :'Scoped::ScopedSubscriberModel', SubscriberModel do
    end

    define_constant :SubscriberDslModel, ActiveRecord::Base do
    end

    define_constant :SubscriberModelBelongsTo, ActiveRecord::Base do
      include Promiscuous::Subscriber

      subscribe :publisher_model_id, :as => :PublisherModelBelongsTo, :from => :test
    end
  end
end
