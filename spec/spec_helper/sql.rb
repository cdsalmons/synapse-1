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

RSpec.configure do |config|
  config.before(:each) do
    ORM.purge!
  end
end
