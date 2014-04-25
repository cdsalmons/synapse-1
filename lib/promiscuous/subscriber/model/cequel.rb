module Promiscuous::Subscriber::Model::Cequel
  extend ActiveSupport::Concern
  include Promiscuous::Subscriber::Model::Base

  module ClassMethods
    def __promiscuous_missing_record_exception
      Cequel::Record::RecordNotFound
    end

    def __promiscuous_duplicate_key_exception?(e)
      # TODO
      false
    end

    def __promiscuous_fetch_existing(id)
      # TODO
      key = subscribe_foreign_key
      if key.to_s == 'id'
        promiscuous_root_class.find(id)
      else
        promiscuous_root_class.__send__("find_by_#{key}", id)
      end
    end
  end
end
