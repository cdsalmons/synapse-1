require 'cequel'

connection = Cequel.connect(:host => 'localhost', :keyspace => 'promiscuous')
if ENV['LOGGER_LEVEL']
  connection.logger = Logger.new(STDOUT).tap { |l| l.level = ENV['LOGGER_LEVEL'].to_i }
end
Cequel::Record.connection = connection

Cequel::Record.connection.schema.drop! rescue nil
Cequel::Record.connection.schema.create!

$need_cequel_migrate = true
module ModelsHelper
  def db_purge!
    return if $need_cequel_migrate
    [:publisher_models, :publisher_model_others,
     :subscriber_models, :subscriber_model_others,
     :publisher_dsl_models, :subscriber_dsl_models,
     :publisher_another_dsl_models, :subscriber_another_dsl_models].each do |table|
       Cequel::Record.connection.execute("TRUNCATE #{table}") rescue nil
     end
  end

  def load_models
    define_constant :PublisherModel do
      include Cequel::Record
      include Promiscuous::Publisher

      key :id, :timeuuid, auto: true
      column :field_1, :text, :index => true
      column :field_2, :text, :index => true
      column :field_3, :text, :index => true
      column :publisher_id, :int

      publish :field_1, :field_2, :field_3
    end

    define_constant :PublisherModelOther do
      include Cequel::Record
      include Promiscuous::Publisher

      key :id, :timeuuid, auto: true
      column :field_1, :text, :index => true
      column :field_2, :text, :index => true
      column :field_3, :text, :index => true
      column :publisher_id, :int

      publish :field_1, :field_2, :field_3
    end


    ##############################################################

    define_constant :SubscriberModel do
      include Cequel::Record
      include Promiscuous::Subscriber

      key :id, :timeuuid, auto: true
      column :field_1, :text, :index => true
      column :field_2, :text, :index => true
      column :field_3, :text, :index => true

      subscribe :field_1, :field_2, :field_3, :as => :PublisherModel, :from => :test
    end

    define_constant :SubscriberModelOther do
      include Cequel::Record
      include Promiscuous::Subscriber

      key :id, :timeuuid, auto: true
      column :field_1, :text, :index => true
      column :field_2, :text, :index => true
      column :field_3, :text, :index => true

      subscribe :field_1, :field_2, :field_3, :as => :PublisherModelOther, :from => :test
    end

    if $need_cequel_migrate
      [PublisherModel, SubscriberModel, PublisherModelOther, SubscriberModelOther].each { |klass| klass.synchronize_schema }
      $need_cequel_migrate = false
    end
  end
end
