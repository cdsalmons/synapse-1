class Promiscuous::Subscriber::Operation::Base
  attr_accessor :model, :id, :operation, :attributes, :routed_attributes
  delegate :message, :to => :message_processor

  def initialize(payload)
    if payload.is_a?(Hash)
      self.id         = payload['id']
      self.operation  = payload['operation'].try(:to_sym)
      self.attributes = payload['attributes']
      if payload['types']
        if route = self.get_route(payload)
          self.model = route[:model]
          self.routed_attributes = route[:attributes]
        end
      end
    end
  end

  def get_route(payload)
    [message.app, '*'].each do |app|
      app_mapping = Promiscuous::Subscriber::Model.mapping[app] || {}
      payload['types'].to_a.each do |ancestor|
        route = app_mapping[ancestor]
        return route if route
      end
    end
    nil
  end

  def warn(msg)
    Promiscuous.warn "[receive] #{msg} #{message.payload}"
  end

  def create(options={})
    model.__promiscuous_fetch_new(id).tap do |instance|
      instance.__promiscuous_update(self)
      instance.save!
    end
  rescue Exception => e
    if model.__promiscuous_duplicate_key_exception?(e)
      options[:on_already_created] ||= proc { warn "ignoring already created record" }
      options[:on_already_created].call
    else
      raise e
    end
  end

  def update(should_create_on_failure=true)
    model.__promiscuous_fetch_existing(id).tap do |instance|
      if instance.__promiscuous_eventual_consistency_update(self)
        instance.__promiscuous_update(self)
        instance.save!
      end
    end
  rescue model.__promiscuous_missing_record_exception
    if should_create_on_failure
      warn "upserting"
      create :on_already_created => proc { update(false) if should_create_on_failure }
    else
      warn "missing record"
    end
  end

  def decorate
    update(false)
  end

  def destroy
    if Promiscuous::Config.consistency == :eventual
      Promiscuous::Subscriber::Worker::EventualDestroyer.postpone_destroy(model, id)
    end

    model.__promiscuous_fetch_existing(id).tap do |instance|
      instance.destroy
    end
  rescue model.__promiscuous_missing_record_exception
    warn "ignoring missing record"
  end
end
