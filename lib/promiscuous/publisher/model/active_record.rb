module Promiscuous::Publisher::Model::ActiveRecord
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Model::Base

  require 'promiscuous/publisher/operation/active_record'

  module ClassMethods
    def __promiscuous_missing_record_exception
      ActiveRecord::RecordNotFound
    end

    def belongs_to(*args, &block)
      super.tap do |association|
        association = association.values.first if association.is_a?(Hash)
        publish(association.foreign_key) if self.in_publish_block?
      end
    end

    def promiscuous_collection_name
      self.table_name
    end
  end
end
