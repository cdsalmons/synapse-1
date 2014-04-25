module Promiscuous::Publisher::Model::Cequel
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Model::Base

  require 'promiscuous/publisher/operation/cequel'

  class PromiscuousMethods
    include Promiscuous::Publisher::Model::Base::PromiscuousMethodsBase

    def missing_attribute_exception
      Cequel::Record::MissingAttributeError
    end
  end

  module ClassMethods
    def __promiscuous_missing_record_exception
      Cequel::Record::RecordNotFound
    end

    def promiscuous_collection_name
      self.table_name
    end
  end
end
