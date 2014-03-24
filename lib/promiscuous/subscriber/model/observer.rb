module Promiscuous::Subscriber::Model::Observer
  extend ActiveSupport::Concern
  include Promiscuous::Subscriber::Model::Base

  included do
    extend ActiveModel::Callbacks
    attr_accessor :id
    define_model_callbacks :save, :create, :update, :destroy
  end

  def __promiscuous_update(payload, options={})
    super
    @payload_operation = payload.operation
  end

  def _save(operation)
    # bubble up to the ephemeral if present
    if respond_to?(:save_operation)
      save_operation(operation)
    end
  end

  def save
    case @payload_operation
    when :create
      run_callbacks :create do
        run_callbacks(:save) { _save(:create) }
      end
    when :update, :decorate
      run_callbacks :update do
        run_callbacks(:save) { _save(:update) }
      end
    when :destroy
      run_callbacks :destroy
    when :bootstrap_data
      run_callbacks :create do
        run_callbacks(:save) { _save(:create) }
      end
    else
      raise "Unknown operation #{@payload_operation}"
    end
  end

  def save!
    save
  end

  def destroy
    run_callbacks :destroy
  end

  module ClassMethods
    def register_klass(options={})
      super
      options[:attributes].each do |attr|
        # TODO do not overwrite existing methods
        attr_accessor attr
      end
    end

    def __promiscuous_fetch_new(id)
      new.tap { |o| o.id = id }
    end
    alias __promiscuous_fetch_existing __promiscuous_fetch_new

    def __promiscuous_duplicate_key_exception?(e)
      false
    end
  end
end
